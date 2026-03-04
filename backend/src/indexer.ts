import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const SUI_RPC_URL = process.env.SUI_RPC_URL || getFullnodeUrl('devnet');
const suiClient = new SuiClient({ url: SUI_RPC_URL });
const PACKAGE_ID = process.env.PACKAGE_ID || '0x8ef483e991274ae8702a598c213c429acb175f5efa26b9ed52ba86c1e67b6d63';

/**
 * Basic Indexer to synchronize Sui Objects with the Database.
 */
export async function syncObjects(address: string) {
  try {
    // 1. Fetch all objects of type 'Capsule' owned by the user (or shared)
    // For now, we fetch by owner address if they are shared or owned.
    const objects = await suiClient.getOwnedObjects({
      owner: address,
      filter: {
        StructType: `${PACKAGE_ID}::capsule_engine::Capsule`,
      },
      options: {
        showContent: true,
      },
    });

    for (const obj of objects.data) {
      const content = obj.data?.content;
      if (content && 'fields' in content) {
        const fields = content.fields as any;
        await prisma.capsule.upsert({
          where: { id: obj.data!.objectId },
          update: {
            title: fields.title,
            description: fields.description,
            category: parseInt(fields.category),
            status: parseInt(fields.status),
            lastPingTsMs: BigInt(fields.last_ping_ts_ms),
            blobId: fields.blob_id,
          },
          create: {
            id: obj.data!.objectId,
            owner: address,
            title: fields.title,
            description: fields.description,
            category: parseInt(fields.category),
            status: parseInt(fields.status),
            lastPingTsMs: BigInt(fields.last_ping_ts_ms),
            blobId: fields.blob_id,
          },
        });
      }
    }
    return true;
  } catch (error) {
    console.error('Indexing Error:', error);
    return false;
  }
}
