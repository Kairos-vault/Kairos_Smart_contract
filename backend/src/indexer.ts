import { SuiJsonRpcClient, getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc';
import { supabase } from './supabase';

const SUI_RPC_URL = process.env.SUI_RPC_URL || getJsonRpcFullnodeUrl('devnet');
const suiClient = new SuiJsonRpcClient({ url: SUI_RPC_URL });
const PACKAGE_ID = process.env.PACKAGE_ID || '0xb82f436cd2c2578eaf2f0ef72687baf86907fba0df05ed2e06c123b2c27adf44';

/**
 * Basic Indexer to synchronize Sui Objects with the Database.
 */
export async function syncObjects(address: string) {
  try {
    // 1. Fetch all objects of type 'Capsule' owned by the user (or shared)
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
        
        const { error } = await supabase.from('Capsule').upsert({
          id: obj.data!.objectId,
          owner: address,
          title: fields.title,
          description: fields.description,
          category: parseInt(fields.category),
          status: parseInt(fields.status),
          lastPingTsMs: fields.last_ping_ts_ms,
          blobId: fields.blob_id,
          updatedAt: new Date().toISOString(),
        }, { onConflict: 'id' });

        if (error) console.error('Supabase Upsert Error:', error);
      }
    }
    return true;
  } catch (error) {
    console.error('Indexing Error:', error);
    return false;
  }
}
