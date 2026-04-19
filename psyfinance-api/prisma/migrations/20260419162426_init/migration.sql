-- CreateEnum
CREATE TYPE "Status" AS ENUM ('ATIVO', 'INATIVO');

-- CreateEnum
CREATE TYPE "PaymentModel" AS ENUM ('SESSAO', 'MENSAL');

-- CreateEnum
CREATE TYPE "Currency" AS ENUM ('BRL', 'EUR');

-- CreateEnum
CREATE TYPE "PaymentStatus" AS ENUM ('PENDENTE', 'PARCIAL', 'PAGO', 'ATRASADO');

-- CreateEnum
CREATE TYPE "ShareType" AS ENUM ('PERCENTAGE', 'FIXED_PER_SESSION');

-- CreateTable
CREATE TABLE "patients" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "cpf" TEXT,
    "location" TEXT NOT NULL,
    "status" "Status" NOT NULL DEFAULT 'ATIVO',
    "paymentModel" "PaymentModel" NOT NULL,
    "currency" "Currency" NOT NULL,
    "notes" TEXT,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "patients_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "rate_history" (
    "id" TEXT NOT NULL,
    "patientId" TEXT NOT NULL,
    "rate" DECIMAL(10,2) NOT NULL,
    "effectiveFrom" DATE NOT NULL,
    "effectiveTo" DATE,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "rate_history_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "session_records" (
    "id" TEXT NOT NULL,
    "patientId" TEXT NOT NULL,
    "year" INTEGER NOT NULL,
    "month" INTEGER NOT NULL,
    "sessionDates" JSONB NOT NULL,
    "sessionCount" INTEGER NOT NULL,
    "expectedAmount" DECIMAL(10,2) NOT NULL,
    "observations" TEXT,
    "isReposicao" BOOLEAN NOT NULL DEFAULT false,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "session_records_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "revenue_share_configs" (
    "id" TEXT NOT NULL,
    "patientId" TEXT NOT NULL,
    "shareType" "ShareType" NOT NULL,
    "shareValue" DECIMAL(10,2) NOT NULL,
    "beneficiaryName" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "revenue_share_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payments" (
    "id" TEXT NOT NULL,
    "sessionRecordId" TEXT NOT NULL,
    "amountPaid" DECIMAL(10,2) NOT NULL DEFAULT 0,
    "status" "PaymentStatus" NOT NULL,
    "revenueShareAmount" DECIMAL(10,2),
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "payments_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "session_records_patientId_year_month_key" ON "session_records"("patientId", "year", "month");

-- CreateIndex
CREATE UNIQUE INDEX "revenue_share_configs_patientId_key" ON "revenue_share_configs"("patientId");

-- CreateIndex
CREATE UNIQUE INDEX "payments_sessionRecordId_key" ON "payments"("sessionRecordId");

-- AddForeignKey
ALTER TABLE "rate_history" ADD CONSTRAINT "rate_history_patientId_fkey" FOREIGN KEY ("patientId") REFERENCES "patients"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "session_records" ADD CONSTRAINT "session_records_patientId_fkey" FOREIGN KEY ("patientId") REFERENCES "patients"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "revenue_share_configs" ADD CONSTRAINT "revenue_share_configs_patientId_fkey" FOREIGN KEY ("patientId") REFERENCES "patients"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_sessionRecordId_fkey" FOREIGN KEY ("sessionRecordId") REFERENCES "session_records"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
