const { HyperFormula } = require('hyperformula');

console.log('📚 HyperFormula 지원 함수 전체 목록');
console.log('=' * 50);

const allFunctions = Object.keys(HyperFormula.getRegisteredFunctionNames('enGB')).sort();

console.log(`총 ${allFunctions.length}개 함수 지원\n`);

// 카테고리별로 분류
const categories = {
  MATH: [],
  LOGICAL: [],
  TEXT: [],
  DATE: [],
  LOOKUP: [],
  STATISTICAL: [],
  FINANCIAL: [],
  OTHER: []
};

allFunctions.forEach(func => {
  const upperFunc = func.toUpperCase();
  
  if (['SUM', 'AVERAGE', 'MAX', 'MIN', 'ABS', 'ROUND', 'SQRT', 'POWER', 'MOD'].some(f => upperFunc.includes(f))) {
    categories.MATH.push(func);
  } else if (['IF', 'AND', 'OR', 'NOT', 'TRUE', 'FALSE'].some(f => upperFunc.includes(f))) {
    categories.LOGICAL.push(func);
  } else if (['TEXT', 'LEFT', 'RIGHT', 'MID', 'LEN', 'UPPER', 'LOWER', 'CONCATENATE'].some(f => upperFunc.includes(f))) {
    categories.TEXT.push(func);
  } else if (['DATE', 'TIME', 'NOW', 'TODAY', 'YEAR', 'MONTH', 'DAY'].some(f => upperFunc.includes(f))) {
    categories.DATE.push(func);
  } else if (['VLOOKUP', 'HLOOKUP', 'INDEX', 'MATCH'].some(f => upperFunc.includes(f))) {
    categories.LOOKUP.push(func);
  } else if (['COUNT', 'COUNTA', 'STDEV', 'VAR'].some(f => upperFunc.includes(f))) {
    categories.STATISTICAL.push(func);
  } else if (['PMT', 'PV', 'FV', 'RATE', 'NPV'].some(f => upperFunc.includes(f))) {
    categories.FINANCIAL.push(func);
  } else {
    categories.OTHER.push(func);
  }
});

// 카테고리별 출력
Object.entries(categories).forEach(([category, functions]) => {
  if (functions.length > 0) {
    console.log(`\n${category} (${functions.length}개):`);
    console.log(functions.slice(0, 20).join(', '));
    if (functions.length > 20) {
      console.log('...');
    }
  }
});

// 주요 함수 검색
console.log('\n🔍 주요 함수 실제 이름 확인:');
const searchTerms = ['SUM', 'AVERAGE', 'MAX', 'MIN', 'COUNT', 'IF', 'VLOOKUP'];

searchTerms.forEach(term => {
  const matches = allFunctions.filter(f => f.toUpperCase().includes(term));
  console.log(`${term} 관련: ${matches.slice(0, 5).join(', ')}`);
});

// 첫 50개 함수 나열
console.log('\n📋 첫 50개 함수:');
for (let i = 0; i < Math.min(50, allFunctions.length); i += 10) {
  const chunk = allFunctions.slice(i, i + 10);
  console.log(`${i.toString().padStart(2, '0')}-${Math.min(i + 9, allFunctions.length - 1).toString().padStart(2, '0')}: ${chunk.join(', ')}`);
}