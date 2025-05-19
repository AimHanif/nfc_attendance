const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');
const users = require('./lib/data/users_seed.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function seed() {
    // Seed users and their subjects
    for (const [docId, userData] of Object.entries(users)) {
        // Clone user data and remove 'subjects' field
        const { subjects, ...baseData } = userData;

        // Write base user document
        await db.collection('users').doc(docId).set(baseData);

        // Write each subject as subcollection
        if (subjects && Array.isArray(subjects)) {
            for (const subject of subjects) {
                // Ensure subject has name and sections
                if (subject.name && subject.sections) {
                    await db.collection('users')
                        .doc(docId)
                        .collection('subjects')
                        .doc(subject.name)
                        .set({ sections: subject.sections });
                }
            }
        }
    }

    console.log('✅ users and subcollections seeded successfully');
    process.exit(0);
}

seed().catch(err => {
    console.error('❌ Seed failed:', err);
    process.exit(1);
});
