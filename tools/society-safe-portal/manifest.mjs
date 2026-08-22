export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
export const SENTINEL_ADDRESS = "0x0000000000000000000000000000000000000001";

export const SAFE_MANIFEST = Object.freeze({
  schemaVersion: 1,
  kind: "society-safe-cross-chain-deployment",
  approvedAt: "2026-08-22",
  deploymentOrder: Object.freeze([8453, 137, 1]),
  chains: Object.freeze({
    1: Object.freeze({
      id: 1,
      hexId: "0x1",
      name: "Ethereum",
      shortName: "Ethereum",
      nativeCurrency: "ETH",
      explorerUrl: "https://etherscan.io",
    }),
    137: Object.freeze({
      id: 137,
      hexId: "0x89",
      name: "Polygon PoS",
      shortName: "Polygon",
      nativeCurrency: "POL",
      explorerUrl: "https://polygonscan.com",
    }),
    8453: Object.freeze({
      id: 8453,
      hexId: "0x2105",
      name: "Base",
      shortName: "Base",
      nativeCurrency: "ETH",
      explorerUrl: "https://basescan.org",
    }),
  }),
  deployer: "0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252",
  safe: Object.freeze({
    release: "1.5.0",
    creationMethod: "createProxyWithNonceL2",
    factory: "0x14F2982D601c9458F93bd70B218933A6f8165e7b",
    factoryCodeHash:
      "0x967dae4cda22b0c9ef7f31b010bdc1ceb0af9904b0c3dc060b5302e4c18a4529",
    proxyCreationCodeHash:
      "0x941b3e88811b2f33b8e26783c7407d2e978404581a21c9f07abf2cad9cb87e12",
    singleton: "0xEdd160fEBBD92E350D4D398fb636302fccd67C7e",
    singletonCodeHash:
      "0x180193227186ccb85316c94db1f0d156ed932b14712cfaac78901899178572dc",
    fallbackHandler: "0x3EfCBb83A4A7AfcB4F68D501E2c2203a38be77f4",
    fallbackHandlerCodeHash:
      "0x3c6a85bcf7b563daa624b884b4e9a1b9fa5371edde7be945d998071a48f28bbc",
    multiSendCallOnly: "0xA83c336B20401Af773B6219BA5027174338D1836",
    multiSendCallOnlyCodeHash:
      "0xcdbdcec38d2f1c7d961b0029ff8416b7e86e9974d6f0e9c9580c7d17fcfb6663",
    saltNonce: 1_151_571_177n,
    predictedAddress: "0x0000fA3e509D629516Ae56dc6FDd31047300114D",
  }),
  initializer: Object.freeze({
    owners: Object.freeze(["0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252"]),
    threshold: 1n,
    setupTo: ZERO_ADDRESS,
    setupData: "0x",
    fallbackHandler: "0x3EfCBb83A4A7AfcB4F68D501E2c2203a38be77f4",
    paymentToken: ZERO_ADDRESS,
    payment: 0n,
    paymentReceiver: ZERO_ADDRESS,
  }),
  finalOwners: Object.freeze([
    "0x098Ec024CbeA5784B842E35972218e0679534258",
    "0x8254D14d8c8c82Bf1f9Be44881Dd535488116605",
    "0xC3E0636c20F1D03Cb2dc7a968996619A43d7B976",
    "0xd397557dE23d587d70b90726cC88a862AFD915D4",
    "0x21a64eF57be4D6930d3eAF84b8362213F5133Af7",
    "0x0A9071538696a7f2e76A6555c1eb8b6a3C030D47",
    "0x2C0e94B4951E084832b966ec5280924bCb4ACe48",
    "0x0aC28e7f11cD5106A8b2606DD916Ee652Fb49f83",
    "0x2E9BFdA965de0EDe0b41D0dEF2aE917708E7cF6D",
    "0xD4Ca157d6ee33a5d0eB811535577cC716b876304",
    "0x7e40Acf1dC4c3e844467299b1070Ae2D1951852c",
    "0x92d35563EA7a4DA571CEA4c15b59f8A9A0975491",
    "0x007546db322B432f82FcF6067cEEe5916a95005C",
    "0x64b7E2076c47701dF987E389eaEB7254F8a80299",
    "0x6c9bB7BBa02404a3Dd0cE572a67a8639af0712Db",
  ]),
  finalThreshold: 7n,
  bootstrapSafeNonce: 0n,
});

export const STORAGE_SLOTS = Object.freeze({
  singleton: 0n,
  fallbackHandler: BigInt(
    "0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5",
  ),
  guard: BigInt(
    "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8",
  ),
});
