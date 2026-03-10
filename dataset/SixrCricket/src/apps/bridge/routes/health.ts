/**
 * @file health.ts
 * @notice Health and metrics endpoint for the Bridge Aggregator
 */

import { Router, Request, Response } from 'express';
import { getLogger } from '../logger';
import { getPayloadCounts, getOldestPendingAge, getTonMultisigCounts } from '../store/payloads';
import { getDatabaseStats, checkDatabaseHealth } from '../store/database';
import { HealthResponse } from '../../shared/types';

/**
 * Creates the health router
 *
 * @returns Express router
 */
export function createHealthRouter(): Router {
  const router = Router();
  const logger = getLogger();

  /**
   * GET /health
   * Returns health status and metrics
   */
  router.get('/', (req: Request, res: Response) => {
    try {
      // Get payload counts
      const counts = getPayloadCounts();

      // Get oldest pending age
      const oldestPendingAge = getOldestPendingAge();

      // Check database health
      let dbHealthy = true;
      try {
        checkDatabaseHealth();
      } catch (err) {
        dbHealthy = false;
        logger.error('Database health check failed', {
          error: err instanceof Error ? err.message : String(err),
        });
      }

      // Determine overall health status
      let status: 'healthy' | 'degraded' | 'unhealthy' = 'healthy';

      // Degraded if there are failed payloads or old pending payloads
      if (counts.failed > 0 || (oldestPendingAge !== null && oldestPendingAge > 600000)) {
        status = 'degraded';
      }

      // Unhealthy if database check failed
      if (!dbHealthy) {
        status = 'unhealthy';
      }

      // Get TON multisig specific counts
      const tonMultisigCounts = getTonMultisigCounts();

      const response: HealthResponse = {
        status,
        timestamp: Date.now(),
        counts,
        oldestPendingAge,
        tonMultisig: {
          readyCount: tonMultisigCounts.ready,
          pendingCount: tonMultisigCounts.pending,
          submittedCount: tonMultisigCounts.submitted,
          confirmedCount: tonMultisigCounts.confirmed,
          failedCount: tonMultisigCounts.failed,
        },
      };

      logger.debug('Health check', response);

      return res.status(status === 'unhealthy' ? 503 : 200).json(response);
    } catch (err) {
      logger.error('Health check failed', {
        error: err instanceof Error ? err.message : String(err),
      });

      return res.status(503).json({
        status: 'unhealthy',
        timestamp: Date.now(),
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  /**
   * GET /metrics
   * Returns detailed metrics about the bridge aggregator
   */
  router.get('/metrics', (req: Request, res: Response) => {
    try {
      const counts = getPayloadCounts();
      const oldestPendingAge = getOldestPendingAge();
      const dbStats = getDatabaseStats();
      const tonMultisigCounts = getTonMultisigCounts();

      const metrics = {
        timestamp: Date.now(),
        payloads: counts,
        tonMultisig: {
          readyCount: tonMultisigCounts.ready,
          pendingCount: tonMultisigCounts.pending,
          submittedCount: tonMultisigCounts.submitted,
          confirmedCount: tonMultisigCounts.confirmed,
          failedCount: tonMultisigCounts.failed,
        },
        database: {
          payloadCount: dbStats.payloadCount,
          signatureCount: dbStats.signatureCount,
          metadataCount: dbStats.metadataCount,
          databaseSize: dbStats.databaseSize,
        },
        health: {
          oldestPendingAge,
          hasPendingPayloads:
            counts.pending > 0 ||
            counts.ready > 0 ||
            counts.burn_pending > 0 ||
            counts.burn_submitted > 0 ||
            counts.burn_confirmed > 0 ||
            counts.ton_mint_pending > 0 ||
            counts.ton_mint_submitted > 0 ||
            counts.ton_mint_confirmed > 0,
          hasFailedPayloads: counts.failed > 0,
        },
      };

      logger.debug('Metrics requested', metrics);

      return res.status(200).json(metrics);
    } catch (err) {
      logger.error('Metrics request failed', {
        error: err instanceof Error ? err.message : String(err),
      });

      return res.status(500).json({
        error: 'Internal error',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  });

  /**
   * GET /ready
   * Kubernetes-style readiness probe
   */
  router.get('/ready', (req: Request, res: Response) => {
    try {
      checkDatabaseHealth();
      return res.status(200).json({ ready: true });
    } catch (err) {
      logger.error('Readiness check failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      return res.status(503).json({ ready: false });
    }
  });

  /**
   * GET /live
   * Kubernetes-style liveness probe
   */
  router.get('/live', (req: Request, res: Response) => {
    return res.status(200).json({ alive: true });
  });

  return router;
}
