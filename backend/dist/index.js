"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const dotenv_1 = __importDefault(require("dotenv"));
const client_1 = require("@prisma/client");
const client_2 = require("@mysten/sui/client");
dotenv_1.default.config();
const app = (0, express_1.default)();
const prisma = new client_1.PrismaClient();
const PORT = process.env.PORT || 3001;
const SUI_RPC_URL = process.env.SUI_RPC_URL || (0, client_2.getFullnodeUrl)('devnet');
const suiClient = new client_2.SuiClient({ url: SUI_RPC_URL });
app.use((0, cors_1.default)());
app.use(express_1.default.json());
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
        const capsules = await prisma.capsule.findMany({
            where: { owner: address },
            include: { beneficiaries: true },
        });
        // Serialize BigInt for JSON
        const serialized = JSON.parse(JSON.stringify(capsules, (key, value) => typeof value === 'bigint' ? value.toString() : value));
        res.json(serialized);
    }
    catch (error) {
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
        const serialized = JSON.parse(JSON.stringify(capsules, (key, value) => typeof value === 'bigint' ? value.toString() : value));
        res.json(serialized);
    }
    catch (error) {
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
