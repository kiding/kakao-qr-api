const
  FUNCTION_NAME = 'kakao-qr-api',
  lambda = new (require('aws-sdk/clients/lambda'))({ apiVersion: '2015-03-31' });

module.exports = {
  get: _ => process.env.MEMORY ? JSON.parse(process.env.MEMORY) : {},
  set: obj => {
    process.env.MEMORY = JSON.stringify(obj);

    return new Promise((resolve, reject) => {
      lambda.getFunctionConfiguration({
        FunctionName: FUNCTION_NAME
      }, (err, data) => {
        if (err) {
          reject(err);
          return;
        }

        let envs = data.Environment.Variables;
        envs.MEMORY = process.env.MEMORY;

        lambda.updateFunctionConfiguration({
          FunctionName: FUNCTION_NAME,
          Environment: { Variables: envs }
        }, (err, data) => {
          if (err) {
            reject(err);
            return;
          }

          resolve(data);
        });
      });
    });
  }
};
