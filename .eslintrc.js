module.exports = {
  env: {
    browser: true,
    es2021: true,
    node: true
  },
  extends: [
    'eslint:recommended'
  ],
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module'
  },
  globals: {
    Stimulus: 'readonly',
    ActionCable: 'readonly',
    Turbo: 'readonly'
  },
  rules: {
    // 코드 품질
    'no-console': 'warn',
    'no-debugger': 'error',
    'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    'no-var': 'error',
    'prefer-const': 'error',
    'prefer-arrow-callback': 'error',
    
    // 코딩 스타일
    'indent': ['error', 2],
    'quotes': ['error', 'double'],
    'semi': ['error', 'always'],
    'comma-dangle': ['error', 'never'],
    'object-curly-spacing': ['error', 'always'],
    'array-bracket-spacing': ['error', 'never'],
    
    // 보안
    'no-eval': 'error',
    'no-implied-eval': 'error',
    'no-new-func': 'error',
    'no-script-url': 'error',
    
    // 성능
    'no-loop-func': 'error',
    'no-inner-declarations': 'error',
    
    // 접근성
    'no-alert': 'warn'
  },
  overrides: [
    {
      files: ['**/*_controller.js'],
      rules: {
        // Stimulus controllers specific rules
        'class-methods-use-this': 'off'
      }
    }
  ]
};