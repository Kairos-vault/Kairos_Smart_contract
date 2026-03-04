import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { PrismaClient } from '@prisma/client';
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { syncObjects } from './indexer';

dotenv.config();

const app = express();
const prisma = new PrismaClient();
const PORT = process.env.PORT || 3001;
const SUI_RPC_URL = process.env.SUI_RPC_URL || getFullnodeUrl('devnet');
const suiClient = new SuiClient({ url: SUI_RPC_URL });

app.use(cors());
app.use(express.json());

// --- Health Check ---
app.get('/health', (req, res) => {
  res.json({ status: 'ok', network: 'sui-devnet' });
});

// --- API Endpoints ---

/**
 * Get all capsules owned by a specific Sui address.
 */
app.get('/api/capsules/owner/:address', async (req, res) => {
  const { address } = req.params;
  try {
    // Attempt to sync from Sui before returning local data
    await syncObjects(address);

    const capsules = await prisma.capsule.findMany({
      where: { owner: address },
      include: { beneficiaries: true },
    });
    
    // Serialize BigInt for JSON
    const serialized = JSON.parse(JSON.stringify(capsules, (key, value) =>
      typeof value === 'bigint' ? value.toString() : value
    ));
    res.json(serialized);
  } catch (error) {
    console.error('Error fetching capsules:', error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

/**
 * Get all capsules where a specific address (or zkIdHash) is a beneficiary.
 */
app.get('/api/capsules/beneficiary/:identifier', async (req, res) => {
  const { identifier } = req.params;
  try {
    const capsules = await prisma.capsule.findMany({
      where: {
        OR: [
          { beneficiaries: { some: { address: identifier } } },
          { beneficiaries: { some: { zkIdHash: identifier } } },
        ],
      },
      include: { beneficiaries: true },
    });
    const serialized = JSON.parse(JSON.stringify(capsules, (key, value) =>
      typeof value === 'bigint' ? value.toString() : value
    ));
    res.json(serialized);
  } catch (error) {
    console.error('Error fetching beneficiary capsules:', error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

/**
 * Manual Trigger for Indexing (Mock for now)
 */
app.post('/api/indexer/trigger', async (req, res) => {
  // In production, this would be a background task or handled by Sui events.
  res.json({ status: 'indexing_triggered' });
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
