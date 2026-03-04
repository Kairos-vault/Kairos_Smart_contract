# Kairos Protocol Backend

The Kairos Protocol Backend is a Node.js/Express service that indexes Sui objects for the Kairos protocol.

## Prerequisites
-   Node.js v18+
-   npm or yarn
-   Aptos CLI (for Move contracts) -> Wait, I mean Sui CLI (since it's Sui)

## Setup
1.  Navigate to the `backend` directory.
2.  Install dependencies: `npm install`
3.  Initialize Prisma: `npx prisma migrate dev --name init`
4.  Copy `.env.example` to `.env` and fill in the details.
5.  Start the development server: `npm run dev`

## Endpoints
-   `GET /health`: Health check.
-   `GET /api/capsules/owner/:address`: Get all capsules owned by a specific Sui address.
-   `GET /api/capsules/beneficiary/:identifier`: Get all capsules where a specific address (or zkIdHash) is a beneficiary.
-   `POST /api/indexer/trigger`: Manual trigger for indexing.
