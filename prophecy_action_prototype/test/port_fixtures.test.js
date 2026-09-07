// 이식 비교 자료 재실행: 기록된 입력 열만으로 같은 결과(결정성). 규칙·수치가 바뀌면 이 테스트가 먼저 깨진다 → tools/port_fixtures.js로 다시 기록
const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('child_process'); const path = require('path');
test('port fixtures: 기록된 입력 열 재실행 결과가 fixtures_v08.json과 일치', () => {
  const out = execFileSync(process.execPath, [path.join(__dirname, '..', 'tools', 'port_fixtures.js'), '--verify'], { encoding: 'utf8' });
  assert.ok(!/FAIL/.test(out), out);
});
