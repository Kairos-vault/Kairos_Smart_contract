-- Create Capsule table
CREATE TABLE "Capsule" (
  "id" TEXT PRIMARY KEY,
  "owner" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "category" INTEGER NOT NULL,
  "blobId" TEXT NOT NULL,
  "status" INTEGER NOT NULL,
  "lastPingTsMs" BIGINT NOT NULL,
  "isActivated" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create Beneficiary table
CREATE TABLE "Beneficiary" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "capsuleId" TEXT NOT NULL REFERENCES "Capsule"("id") ON DELETE CASCADE,
  "address" TEXT,
  "zkIdHash" TEXT,
  "role" INTEGER NOT NULL,
  "hasApproved" BOOLEAN NOT NULL DEFAULT false
);

-- Add some useful indexes for querying
CREATE INDEX idx_capsule_owner ON "Capsule"("owner");
CREATE INDEX idx_beneficiary_capsule_id ON "Beneficiary"("capsuleId");
CREATE INDEX idx_beneficiary_address ON "Beneficiary"("address");
CREATE INDEX idx_beneficiary_zkidhash ON "Beneficiary"("zkIdHash");
