/**
 * @typedef {Object} CompilerInput
 */

/**
 * @typedef {Object} EtherscanVerifyRequest
 * @property {string} apikey
 * @property {string} module
 * @property {string} codeformat
 * @property {string} action
 * @property {string} contractaddress
 * @property {string} sourceCode
 * @property {string} contractname
 * @property {string} compilerversion
 * @property {string} constructorArguements
 */

/**
 * @typedef {Object} IEtherscanApiResponse
 * @property {string} message
 * @property {string} result
 * @property {string} status
 */

/**
 * @type {Object.<string, string>}
 */
const etherscanApis = {
  mainnet: "https://api.etherscan.io/api",
  goerli: "https://api-goerli.etherscan.io/api",
  sepolia: "https://api-sepolia.etherscan.io/api",
};

/**
 * @param {Object} params
 * @param {string} params.contractName
 * @param {string} params.contractAddress
 * @param {string} params.etherscanApiKey
 * @param {string} params.constructorArguments
 * @param {string} params.compilerVersion
 * @param {CompilerInput} params.source
 * @returns {EtherscanVerifyRequest}
 */
export function etherscanVerificationRequest({
  contractName,
  contractAddress,
  constructorArguments,
  compilerVersion,
  etherscanApiKey,
  source,
}) {
  return {
    apikey: etherscanApiKey,
    module: "contract",
    codeformat: "solidity-standard-json-input",
    action: "verifysourcecode",
    contractaddress: contractAddress,
    sourceCode: JSON.stringify(source),
    contractname: contractName,
    compilerversion: `v${compilerVersion}`,
    constructorArguements: constructorArguments,
  };
}

/**
 * @param {IEtherscanApiResponse} response
 * @returns {boolean}
 */
function isResponseVerificationPending(response) {
  return response.message === "NOTOK" && response.result === "Pending in queue";
}

/**
 * @param {IEtherscanApiResponse} response
 * @returns {boolean}
 */
function isResponseVerificationFailure(response) {
  return (
    response.message === "NOTOK" &&
    response.result === "Fail - Unable to verify"
  );
}

/**
 * @param {IEtherscanApiResponse} response
 * @returns {boolean}
 */
function isResponseVerificationSuccess(response) {
  return (
    (response.message === "OK" && response.result === "Pass - Verified") ||
    (response.message === "NOTOK" && response.result === "Already Verified")
  );
}
