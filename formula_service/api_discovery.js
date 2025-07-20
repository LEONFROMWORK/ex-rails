const { HyperFormula } = require('hyperformula');

console.log('🔍 HyperFormula 정확한 API 탐색');

// 인스턴스 생성
const hf = HyperFormula.buildEmpty({
  licenseKey: 'gpl-v3'
});

console.log('✅ HyperFormula 인스턴스 생성');

// 모든 인스턴스 메소드 출력
const instanceMethods = Object.getOwnPropertyNames(Object.getPrototypeOf(hf))
  .filter(name => typeof hf[name] === 'function')
  .sort();

console.log('\n📋 사용 가능한 인스턴스 메소드들:');
instanceMethods.forEach(method => {
  console.log(`  - ${method}`);
});

// 클래스 메소드 출력
const classMethods = Object.getOwnPropertyNames(HyperFormula)
  .filter(name => typeof HyperFormula[name] === 'function')
  .sort();

console.log('\n📋 사용 가능한 클래스 메소드들:');
classMethods.forEach(method => {
  console.log(`  - ${method}`);
});

// 기본 데이터로 HyperFormula 생성 테스트
console.log('\n🧪 기본 데이터 테스트:');
try {
  const data = [
    [1, 2, '=A1+B1'],
    [4, 5, '=A2+B2']
  ];
  
  const hfWithData = HyperFormula.buildFromArray(data, {
    licenseKey: 'gpl-v3'
  });
  
  console.log('✅ 배열에서 HyperFormula 생성 성공');
  console.log(`C1 값: ${hfWithData.getCellValue({ sheet: 0, row: 0, col: 2 })}`);
  console.log(`C2 값: ${hfWithData.getCellValue({ sheet: 0, row: 1, col: 2 })}`);
  console.log(`C1 수식: ${hfWithData.getCellFormula({ sheet: 0, row: 0, col: 2 })}`);
  
} catch (error) {
  console.log(`❌ 오류: ${error.message}`);
}