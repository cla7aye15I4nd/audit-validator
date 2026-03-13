/**
 * @file check-health.ts
 * @notice Simple script to check Bridge Aggregator health
 */

import 'dotenv/config';

async function main() {
  const aggregatorUrl = process.env.BRIDGE_AGGREGATOR_URL || 'http://localhost:3000';

  console.log('Bridge Aggregator Health Check');
  console.log('===============================\n');
  console.log(`URL: ${aggregatorUrl}\n`);

  try {
    // Check root endpoint
    console.log('Checking root endpoint...');
    const rootResponse = await fetch(aggregatorUrl);
    const rootData = await rootResponse.json();
    console.log('Root:', JSON.stringify(rootData, null, 2), '\n');

    // Check health endpoint
    console.log('Checking health endpoint...');
    const healthResponse = await fetch(`${aggregatorUrl}/health`);
    const healthData = await healthResponse.json();
    console.log('Health:', JSON.stringify(healthData, null, 2), '\n');

    // Check metrics endpoint
    console.log('Checking metrics endpoint...');
    const metricsResponse = await fetch(`${aggregatorUrl}/health/metrics`);
    const metricsData = await metricsResponse.json();
    console.log('Metrics:', JSON.stringify(metricsData, null, 2), '\n');

    if (healthData.status === 'healthy') {
      console.log('✓ Bridge Aggregator is healthy!');
    } else {
      console.log(`⚠ Bridge Aggregator status: ${healthData.status}`);
    }
  } catch (err) {
    console.error('Error connecting to Bridge Aggregator:');
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Error:', err.message);
    process.exit(1);
  });
