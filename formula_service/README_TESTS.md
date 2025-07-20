# Formula Service Test Files

This directory contains test files that were created during development. These files are excluded from git tracking.

## Test Files Location

All test files have been moved to the `tests/` directory:

- `tests/test_hyperformula.js` - HyperFormula functionality tests
- `tests/simple_test.js` - Basic API validation tests
- `tests/language_test.js` - Language configuration tests  
- `tests/comprehensive_test.js` - Comprehensive feature tests
- `tests/working_test.js` - Working integration tests
- `tests/test_client.js` - API test client
- `tests/test_v3_compatibility.js` - v3 API compatibility tests
- `tests/performance_test.js` - Performance benchmarks
- `tests/integration_examples.js` - Integration usage examples
- `tests/test_formulas.xlsx` - Test Excel file

## Running Tests

To run specific tests:

```bash
cd formula_service
node tests/simple_test.js
node tests/performance_test.js
```

## Note

These test files are for development purposes only and should not be deployed to production.