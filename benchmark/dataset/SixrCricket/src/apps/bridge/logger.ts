/**
 * @file logger.ts
 * @notice Structured logging for the Bridge Aggregator
 */

import winston from 'winston';
import { BridgeConfig } from './config';

let logger: winston.Logger;

/**
 * Initializes the logger with configuration
 *
 * @param config - Bridge configuration
 */
export function initializeLogger(config: BridgeConfig): void {
  const format =
    config.logging.format === 'json'
      ? winston.format.combine(winston.format.timestamp(), winston.format.json())
      : winston.format.combine(
          winston.format.timestamp(),
          winston.format.colorize(),
          winston.format.printf(
            ({ timestamp, level, message, ...meta }) =>
              `${timestamp} [${level}]: ${message} ${Object.keys(meta).length ? JSON.stringify(meta) : ''}`
          )
        );

  logger = winston.createLogger({
    level: config.logging.level,
    format,
    transports: [new winston.transports.Console()],
  });
}

/**
 * Gets the logger instance
 *
 * @returns Winston logger
 */
export function getLogger(): winston.Logger {
  if (!logger) {
    // Fallback logger if not initialized
    logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
      transports: [new winston.transports.Console()],
    });
  }
  return logger;
}
