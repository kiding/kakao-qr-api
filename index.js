const
  USER_AGENT = 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 KAKAOTALK 9.0.3',
  chromium = require('chrome-aws-lambda'),
  fetch = require('node-fetch'),
  memory = require('./memory');

async function login() {
  console.log('Creating browser...');
  const browser = await chromium.puppeteer.launch({
    args: chromium.args,
    defaultViewport: { width: 375, height: 667, deviceScaleFactor: 2 },
    executablePath: await chromium.executablePath,
    headless: chromium.headless,
  });

  console.log('Creating page...');
  const page = await browser.newPage();
  await page.setUserAgent(USER_AGENT);

  console.log('Opening the login page...');
  await page.goto('https://accounts.kakao.com/login?continue=https%3A%2F%2Faccounts.kakao.com%2Fweblogin%2Faccount%2Finfo');
  await page.waitForSelector('#login-form');

  console.log('Logging in...');
  await page.$eval('#id_email_2', (node, value) => node.value = value, process.env.KAKAO_USERNAME);
  await page.$eval('#id_password_3', (node, value) => node.value = value, process.env.KAKAO_PASSWORD);
  await (await page.$('button.submit')).click();
  await page.waitForResponse('https://accounts.kakao.com/weblogin/account/info')
  const _kawlt = (await page.cookies()).filter(({ name }) => name === '_kawlt')[0].value;

  console.log('Closing the browser...');
  await browser.close();

  return _kawlt;
}

async function check_in(_kawlt) {
  const headers = { 'Cookie': `_kawlt=${encodeURIComponent(_kawlt)}`, 'User-Agent': USER_AGENT };

  console.log('Fetching data...');
  const html = await (await fetch('https://accounts.kakao.com/qr_check_in', { headers })).text();
  const { groups: { token } } = html.match(/"token":\s*"(?<token>.+?)"/);

  const json = await (await fetch(`https://accounts.kakao.com/qr_check_in/request_qr_data.json?lang=ko&os=ios&webview_v=2&is_under_age=false&token=${token}`, { headers })).json();
  return json.qr_data;
}

exports.handler = async () => {
  var qr_data = '';

  try {
    const { _kawlt } = memory.get();
    qr_data = await check_in(_kawlt);
  } catch (e) {
    console.warn(e.message);

    const _kawlt = await login();
    memory.set({ _kawlt });
    qr_data = await check_in(_kawlt);
  } finally {
    console.log('Done!');
    return { statusCode: 200, body: qr_data };
  }
};
