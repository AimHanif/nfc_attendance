// seed.js
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');
const users = require('./lib/data/users_seed.json');

admin.initializeApp({
credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function seed() {
const batch = db.batch();
for (const [docId, data] of Object.entries(users)) {
const ref = db.collection('users').doc(docId);
batch.set(ref, data);
}
await batch.commit();
console.log('✅ users collection seeded successfully');
process.exit(0);
}

seed().catch(err => {
console.error('❌ Seed failed:', err);
process.exit(1);
});
