#!/usr/bin/env node
'use strict';

const fs = require('fs');

const projectId = process.env.FIREBASE_PROJECT_ID || 'sharesync-56711';

function readServiceAccountJson() {
  const inline =
    process.env.FIREBASE_SERVICE_ACCOUNT_SHARESYNC_56711 ||
    process.env.FIREBASE_SERVICE_ACCOUNT ||
    process.env.FIREBASE_SERVICE_ACCOUNT_JSON ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON;

  if (inline) {
    return JSON.parse(inline);
  }

  const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (credentialsPath && fs.existsSync(credentialsPath)) {
    return JSON.parse(fs.readFileSync(credentialsPath, 'utf8'));
  }

  return null;
}

function printIamFix(email) {
  console.log('');
  console.log('Firestore rules deploy needs extra IAM on the CI service account.');
  console.log(`Service account: ${email}`);
  console.log(`Project: ${projectId}`);
  console.log('');
  console.log('Grant at least one of these roles on the project:');
  console.log('  - roles/firebaserules.admin   (Firebase Rules Admin)');
  console.log('  - roles/firebase.admin        (Firebase Admin, broader)');
  console.log('');
  console.log('Google Cloud IAM (pick the service account above):');
  console.log(
    `  https://console.cloud.google.com/iam-admin/iam?project=${projectId}`,
  );
  console.log('');
  console.log('Or with gcloud (run as a project Owner):');
  console.log(
    `  gcloud projects add-iam-policy-binding ${projectId} \\`,
  );
  console.log(`    --member="serviceAccount:${email}" \\`);
  console.log('    --role="roles/firebaserules.admin"');
  console.log('');
  console.log('Manual rules publish (one-time fallback):');
  console.log(
    `  https://console.firebase.google.com/project/${projectId}/firestore/rules`,
  );
}

const account = readServiceAccountJson();
if (!account?.client_email) {
  console.error('Could not determine Firebase deploy service account.');
  process.exit(1);
}

console.log(`Firebase deploy service account: ${account.client_email}`);

if (process.argv.includes('--iam-help')) {
  printIamFix(account.client_email);
}
