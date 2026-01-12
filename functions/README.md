# Cloud Functions Setup

## Quick Start

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Create `.env` file for local testing:**
   ```bash
   BOKUN_ACCESS_KEY=your_actual_access_key
   BOKUN_SECRET_KEY=your_actual_secret_key
   ```

3. **Set production secrets:**
   ```bash
   firebase functions:secrets:set BOKUN_ACCESS_KEY
   firebase functions:secrets:set BOKUN_SECRET_KEY
   ```

4. **Deploy:**
   ```bash
   cd ..
   firebase deploy --only functions
   ```

## Environment Variables

The function uses `process.env.BOKUN_ACCESS_KEY` and `process.env.BOKUN_SECRET_KEY`.

- **Local development**: Set these in `functions/.env` (gitignored)
- **Production**: Set using `firebase functions:secrets:set` (these become environment variables automatically)

## Notes

- Node.js 22 is required (as specified in package.json)
- Firebase Functions SDK v7 is used (latest)
- The deprecated `functions.config()` API has been removed


