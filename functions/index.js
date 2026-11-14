const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();

const STORE_ID = "khan-baba-general-store";

exports.createSalesman = onCall({ region: "asia-south1" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Please sign in first.");
  }

  const db = getFirestore();
  const memberRef = db.collection("stores").doc(STORE_ID)
    .collection("members").doc(request.auth.uid);
  const member = await memberRef.get();

  if (!member.exists || member.data().active !== true ||
      member.data().role !== "admin") {
    throw new HttpsError("permission-denied", "Only an active store admin can create accounts.");
  }

  const email = String(request.data?.email || "").trim().toLowerCase();
  const password = String(request.data?.password || "");
  const name = String(request.data?.name || "").trim();

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  if (password.length < 8) {
    throw new HttpsError("invalid-argument", "Password must be at least 8 characters.");
  }
  if (!name || name.length > 80) {
    throw new HttpsError("invalid-argument", "Enter a valid name.");
  }

  let createdUser;
  try {
    createdUser = await getAuth().createUser({
      email, password, displayName: name, disabled: false
    });

    await db.collection("stores").doc(STORE_ID).collection("members")
      .doc(createdUser.uid).create({
        name, email, role: "salesman", active: true,
        createdAt: FieldValue.serverTimestamp(),
        createdBy: request.auth.uid
      });

    return { uid: createdUser.uid, email, name };
  } catch (error) {
    if (createdUser) {
      await getAuth().deleteUser(createdUser.uid).catch(() => {});
    }
    if (error instanceof HttpsError) throw error;
    if (error.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "This email is already registered.");
    }
    throw new HttpsError("internal", "Salesman account could not be created.");
  }
});
