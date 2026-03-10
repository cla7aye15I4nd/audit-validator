#!/usr/bin/env node
/**
 * @file bridge.ts
 * @notice Main entrypoint for the Bridge Aggregator service
 *
 * This service coordinates watcher signatures for bridge payloads, persists progress,
 * and submits finalized multisig transactions once quorum requirements are met.
 *
 * The aggregator replaces the ad-hoc manual pipeline (prepare-ton-to-base.ts / execute-mint.ts)
 * and becomes the single system of record between TON burns and Base mints.
 */

import express, { Express, Request, Response, NextFunction } from 'express';
import { loadConfig, printConfigSummary, validateConfig } from './config';
import { initializeLogger, getLogger } from './logger';
import { initializeDatabase, closeDatabase, runMigrations } from './store/database';
import { createPayloadsRouter } from './routes/payloads';
import { createHealthRouter } from './routes/health';
import { SubmissionWorker } from './workers/submitter';
import { TonBurnWorker } from './workers/ton-burner';
import { TonMintWorker } from './workers/ton-minter';
import { TonMultisigSubmitter } from './workers/ton-multisig-submitter';

/**
 * Enable BigInt JSON serialization
 * better-sqlite3 with defaultSafeIntegers(true) returns BigInt values,
 * which need to be serialized as strings to avoid JSON.stringify errors
 */
declare global {
  interface BigInt {
    toJSON(): string;
  }
}

BigInt.prototype.toJSON = function(): string {
  return this.toString();
};

/**
 * Bridge Aggregator service
 */
class BridgeAggregator {
  private app: Express;
  private config: ReturnType<typeof loadConfig>;
  private logger: ReturnType<typeof getLogger>;
  private submissionWorker: SubmissionWorker | null = null;
  private tonBurnWorker: TonBurnWorker | null = null;
  private tonMintWorker: TonMintWorker | null = null;
  private tonMultisigSubmitter: TonMultisigSubmitter | null = null;
  private server: any = null;

  constructor() {
    // Validate configuration
    const validation = validateConfig();
    if (!validation.valid) {
      console.error('Configuration validation failed:');
      validation.errors.forEach((err) => console.error(`  - ${err}`));
      process.exit(1);
    }

    // Load configuration
    this.config = loadConfig();

    // Initialize logger
    initializeLogger(this.config);
    this.logger = getLogger();

    // Print configuration summary
    printConfigSummary(this.config);

    // Initialize database
    try {
      const db = initializeDatabase({
        path: this.config.database.path,
        verbose: this.config.database.verbose,
      });
      this.logger.info('Database initialized', {
        path: this.config.database.path,
      });

      // Run migrations
      runMigrations(db);
      this.logger.info('Database migrations completed');
    } catch (err) {
      this.logger.error('Failed to initialize database', {
        error: err instanceof Error ? err.message : String(err),
      });
      process.exit(1);
    }

    // Initialize Express app
    this.app = express();

    // Setup middleware
    this.setupMiddleware();

    // Setup routes
    this.setupRoutes();

    // Setup error handler
    this.setupErrorHandler();

    // Initialize submission worker
    this.submissionWorker = new SubmissionWorker(this.config);

    // Initialize TON burn worker if enabled
    if (this.config.tonBurner.enabled) {
      try {
        this.tonBurnWorker = new TonBurnWorker(this.config);
      } catch (err) {
        this.logger.error('Failed to initialize TON burn worker', {
          error: err instanceof Error ? err.message : String(err),
        });
        // Don't exit - continue without burn worker (backward compatible)
      }
    }

    // Initialize TON mint worker if enabled (LEGACY)
    if (this.config.tonMinter.enabled) {
      try {
        this.tonMintWorker = new TonMintWorker(this.config);
      } catch (err) {
        this.logger.error('Failed to initialize TON mint worker', {
          error: err instanceof Error ? err.message : String(err),
        });
        // Don't exit - continue without mint worker (backward compatible)
      }
    }

    // Initialize TON multisig submitter if enabled (EVM -> TON)
    if (this.config.tonMultisigSubmitter.enabled) {
      try {
        this.tonMultisigSubmitter = new TonMultisigSubmitter(this.config);
      } catch (err) {
        this.logger.error('Failed to initialize TON multisig submitter', {
          error: err instanceof Error ? err.message : String(err),
        });
        // Don't exit - continue without multisig submitter (backward compatible)
      }
    }
  }

  /**
   * Sets up Express middleware
   */
  private setupMiddleware(): void {
    // Parse JSON bodies
    this.app.use(express.json());

    // Request logging middleware
    this.app.use((req: Request, res: Response, next: NextFunction) => {
      const start = Date.now();

      res.on('finish', () => {
        const duration = Date.now() - start;
        this.logger.info('HTTP request', {
          method: req.method,
          path: req.path,
          status: res.statusCode,
          duration,
          ip: req.ip,
        });
      });

      next();
    });

    // CORS headers (allow all origins for development)
    this.app.use((req: Request, res: Response, next: NextFunction) => {
      res.header('Access-Control-Allow-Origin', '*');
      res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-API-Key');

      if (req.method === 'OPTIONS') {
        return res.sendStatus(200);
      }

      next();
    });
  }

  /**
   * Creates API key authentication middleware
   * Only validates if BRIDGE_API_KEY is configured
   */
  private createApiKeyMiddleware(): (req: Request, res: Response, next: NextFunction) => void {
    return (req: Request, res: Response, next: NextFunction) => {
      const configuredApiKey = this.config.security.apiKey;

      // If no API key is configured, allow all requests
      if (!configuredApiKey) {
        return next();
      }

      const providedApiKey = req.headers['x-api-key'] as string;

      if (!providedApiKey) {
        this.logger.warn('API key missing', {
          path: req.path,
          method: req.method,
          ip: req.ip,
        });
        return res.status(401).json({
          error: 'Unauthorized',
          message: 'API key is required. Provide X-API-Key header.',
        });
      }

      if (providedApiKey !== configuredApiKey) {
        this.logger.warn('Invalid API key', {
          path: req.path,
          method: req.method,
          ip: req.ip,
        });
        return res.status(401).json({
          error: 'Unauthorized',
          message: 'Invalid API key.',
        });
      }

      next();
    };
  }

  /**
   * Sets up API routes
   */
  private setupRoutes(): void {
    // Root endpoint
    this.app.get('/', (req: Request, res: Response) => {
      res.json({
        service: 'Bridge Aggregator',
        version: '1.0.0',
        status: 'running',
        workers: {
          submission: this.submissionWorker?.getStatus(),
          tonBurner: this.tonBurnWorker?.getStatus() || { running: false, enabled: this.config.tonBurner.enabled },
          tonMinter: this.tonMintWorker?.getStatus() || { running: false, enabled: this.config.tonMinter.enabled },
          tonMultisigSubmitter: this.tonMultisigSubmitter?.getStatus() || { running: false, enabled: this.config.tonMultisigSubmitter.enabled },
        },
      });
    });

    // Mount routes
    // /payloads requires API key authentication (if configured)
    this.app.use('/payloads', this.createApiKeyMiddleware(), createPayloadsRouter(this.config));
    // /health is public (for load balancer health checks)
    this.app.use('/health', createHealthRouter());

    // 404 handler
    this.app.use((req: Request, res: Response) => {
      res.status(404).json({
        error: 'Not found',
        message: `Route ${req.method} ${req.path} not found`,
      });
    });
  }

  /**
   * Sets up global error handler
   */
  private setupErrorHandler(): void {
    this.app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
      this.logger.error('Unhandled error', {
        error: err.message,
        stack: err.stack,
        path: req.path,
        method: req.method,
      });

      res.status(500).json({
        error: 'Internal server error',
        message: err.message,
      });
    });
  }

  /**
   * Starts the service
   */
  public async start(): Promise<void> {
    // Start HTTP server
    this.server = this.app.listen(this.config.network.port, this.config.network.host, () => {
      this.logger.info('Bridge Aggregator started', {
        host: this.config.network.host,
        port: this.config.network.port,
      });
    });

    // Start TON burn worker first (if enabled)
    if (this.tonBurnWorker) {
      this.tonBurnWorker.start();
    }

    // Start TON mint worker (for EVM -> TON flow) - LEGACY
    if (this.tonMintWorker) {
      this.tonMintWorker.start();
    }

    // Start TON multisig submitter (for EVM -> TON flow)
    if (this.tonMultisigSubmitter) {
      this.tonMultisigSubmitter.start();
    }

    // Start submission worker (processes payloads after burn confirmation)
    if (this.submissionWorker) {
      this.submissionWorker.start();
    }

    // Setup graceful shutdown
    this.setupGracefulShutdown();
  }

  /**
   * Sets up graceful shutdown handlers
   */
  private setupGracefulShutdown(): void {
    const shutdown = async (signal: string) => {
      this.logger.info('Received shutdown signal', { signal });

      // Stop accepting new requests
      if (this.server) {
        this.server.close(() => {
          this.logger.info('HTTP server closed');
        });
      }

      // Stop workers
      if (this.tonBurnWorker) {
        this.tonBurnWorker.stop();
      }

      if (this.tonMintWorker) {
        this.tonMintWorker.stop();
      }

      if (this.tonMultisigSubmitter) {
        this.tonMultisigSubmitter.stop();
      }

      if (this.submissionWorker) {
        this.submissionWorker.stop();
      }

      // Close database
      closeDatabase();
      this.logger.info('Database closed');

      this.logger.info('Graceful shutdown complete');
      process.exit(0);
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));

    process.on('unhandledRejection', (reason, promise) => {
      this.logger.error('Unhandled promise rejection', {
        reason: reason instanceof Error ? reason.message : String(reason),
        stack: reason instanceof Error ? reason.stack : undefined,
      });
    });

    process.on('uncaughtException', (err) => {
      this.logger.error('Uncaught exception', {
        error: err.message,
        stack: err.stack,
      });
      process.exit(1);
    });
  }

  /**
   * Stops the service
   */
  public async stop(): Promise<void> {
    this.logger.info('Stopping Bridge Aggregator');

    if (this.server) {
      this.server.close();
    }

    if (this.tonBurnWorker) {
      this.tonBurnWorker.stop();
    }

    if (this.tonMintWorker) {
      this.tonMintWorker.stop();
    }

    if (this.tonMultisigSubmitter) {
      this.tonMultisigSubmitter.stop();
    }

    if (this.submissionWorker) {
      this.submissionWorker.stop();
    }

    closeDatabase();
  }
}

/**
 * Main entry point
 */
async function main(): Promise<void> {
  console.log('========================================');
  console.log('Bridge Aggregator');
  console.log('========================================\n');

  const aggregator = new BridgeAggregator();
  await aggregator.start();
}

// Run if executed directly
if (require.main === module) {
  main().catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
}

export { BridgeAggregator };
