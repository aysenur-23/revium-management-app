
const { google } = require('googleapis');
const fs = require('fs');

async function checkSheet() {
    const auth = new google.auth.GoogleAuth({
        keyFile: './service-account.json',
        scopes: ['https://www.googleapis.com/auth/spreadsheets.readonly'],
    });

    const drive = google.drive({ version: 'v3', auth });
    const sheets = google.sheets({ version: 'v4', auth });

    const ids = [
        '1DflGMFqoS4PgmjD8Ekcx29WZgxMEmJ5AKq23E6bxcDw', // Main
        '1ZjeJIJ3h0MaHEbmDIM5N-mRKI2YxKuOM'            // User provided
    ];

    for (const spreadsheetId of ids) {
        console.log(`\n--- File: ${spreadsheetId} ---`);
        try {
            const file = await drive.files.get({ fileId: spreadsheetId, fields: 'name, mimeType, webViewLink', supportsAllDrives: true });
            console.log(`Name: ${file.data.name}`);
            console.log(`MimeType: ${file.data.mimeType}`);

            if (file.data.mimeType === 'application/vnd.google-apps.spreadsheet') {
                const res = await sheets.spreadsheets.get({ spreadsheetId });
                console.log(`Sheets: ${res.data.sheets.map(s => s.properties.title).join(', ')}`);
                const targetSheet = res.data.sheets.find(s => s.properties.title.includes('Sabit')) || res.data.sheets[0];
                const range = `${targetSheet.properties.title}!A1:E5`;
                const data = await sheets.spreadsheets.values.get({ spreadsheetId, range });
                console.log(`Sample Data from "${targetSheet.properties.title}":`);
                console.log(JSON.stringify(data.data.values, null, 2));
            } else {
                console.log('Not a native Google Sheet.');
            }
        } catch (e) {
            console.error(`Error: ${e.message}`);
        }
    }
}

checkSheet();
