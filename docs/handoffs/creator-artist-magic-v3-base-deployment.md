# CreatorArtistMagic V3 Base deployment handoff

Status: **complete and verified**

The CreatorArtistMagic V3 stack was deployed to Base on 2026-08-11 from commit `00accdf`. Foundry broadcast all transactions sequentially with the Doppler `prd` RPC. Every receipt has status `1`. The independent `verifyDeployed()` pass completed after the broadcast and before any legacy provider withdrawal.

## Canonical contracts

| Contract | Address | Explorer |
| --- | --- | --- |
| CreatorArtistMagic V3 | `0x6754e4871775A781702f2Ab6e494754a562586ee` | [BaseScan](https://basescan.org/address/0x6754e4871775A781702f2Ab6e494754a562586ee#code) |
| UniversalPoolArtMarketplace V3 | `0x93222897902a5Fc2f20079d242c660117277930A` | [BaseScan](https://basescan.org/address/0x93222897902a5Fc2f20079d242c660117277930A#code) |
| FameMarketplaceCheckout V3 | `0x50B9649Aa28D7d0B966B2A51092C5BcF37905a63` | [BaseScan](https://basescan.org/address/0x50B9649Aa28D7d0B966B2A51092C5BcF37905a63#code) |
| Legacy marketplace, withdrawal only | `0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e` | [BaseScan](https://basescan.org/address/0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e) |

All three new contracts passed BaseScan source verification during the Foundry broadcast.

## Receipt ledger

| # | Operation | Block | Transaction |
| ---: | --- | ---: | --- |
| 1 | Pause legacy marketplace | 49840113 | [`0x7671e0ae...cfad`](https://basescan.org/tx/0x7671e0ae2b8c6ff91611850800464f853b2f8d44e67cddf7a306e4d1df13cfad) |
| 2 | Deploy CreatorArtistMagic V3 | 49840114 | [`0xc53af62d...9416`](https://basescan.org/tx/0xc53af62d30e7aae80ef0e9fdadd5d5736c8c456ebdc62447e98789de6e689416) |
| 3 | Grant creator 1 | 49840115 | [`0xc3af4969...de50`](https://basescan.org/tx/0xc3af4969c2c39ff8f2bc777258e3377b59818e857b72a5f4c1410c723733de50) |
| 4 | Grant creator 2 | 49840117 | [`0x6e8d1b5d...2d87`](https://basescan.org/tx/0x6e8d1b5dfe970ae2dae841180786c3ad1a00126af33d891ebc2766b8f1062d87) |
| 5 | Grant creator 3 | 49840118 | [`0x945ea394...a21`](https://basescan.org/tx/0x945ea3949cbfacef6dba8899cddeab97ac38982e1ca5f308b89f4558826fda21) |
| 6 | Set FAME renderer to V3 | 49840119 | [`0xf619f5f7...a272`](https://basescan.org/tx/0xf619f5f7325ce2c235cdb191b41e2020ac588ee9c70d26975b6825ecc3a2a272) |
| 7 | Deploy replacement marketplace | 49840120 | [`0x58e4cdcc...3262`](https://basescan.org/tx/0x58e4cdcc14b9df30372e1ff4ad34e2220a8bff4578b8baa461973eab96233262) |
| 8 | Grant replacement marketplace BANISHER | 49840121 | [`0x889245c8...b1d6`](https://basescan.org/tx/0x889245c87f64f1c31c963a1e5b44243e4dec09d80a952f48a295516eb2f7b1d6) |
| 9 | Deploy replacement checkout | 49840123 | [`0xf5427c66...707d`](https://basescan.org/tx/0xf5427c66f28196a2390231b26f0262850a2c2d1c94783f6c07374cd3d874707d) |
| 10 | Authorize replacement checkout | 49840124 | [`0xe60bf563...6a5c`](https://basescan.org/tx/0xe60bf5639d23d8177a4f8a60c5a8f7fe25ac8fd095167302db41129d70006a5c) |
| 11 | Unpause replacement marketplace | 49840126 | [`0xdc6b6150...3679`](https://basescan.org/tx/0xdc6b6150eedfc0af98fd405ef3a800e33733d2e9452c74cadc05bfd40f093679) |
| 12 | Revoke creator 1 from V2 | 49840128 | [`0xe667e6db...93e1`](https://basescan.org/tx/0xe667e6dbe78d1a6dd91161eb20ff080deb94fd5714a9d76cb4b51f047dc393e1) |
| 13 | Revoke creator 2 from V2 | 49840129 | [`0x8d3e5e5a...c2ec`](https://basescan.org/tx/0x8d3e5e5afb88067385169097130381db5bfb4734b1402f3d1c524577e4b9c2ec) |
| 14 | Revoke creator 3 from V2 | 49840130 | [`0x1e442c25...2361`](https://basescan.org/tx/0x1e442c25f26e19289c79a11c8d80f982021e10688c181f5fe03c1f3099072361) |
| 15 | Revoke legacy marketplace write role from V2 | 49840131 | [`0x71178336...bae9`](https://basescan.org/tx/0x711783362dbe6b8d114409ffda4201901cba445897c98b51d3c1908b9b16bae9) |

## Verified post-state

The live verifier confirmed:

- FAME renders through `V3 -> V2 -> prior renderer`.
- V3 retains `nextTokenId = 651`, `artPoolNext = 266`, its FAME binding, ownership, and exact creator/renderer/banisher roles.
- The replacement marketplace is bound to V3, unpaused, authorized to use the replacement checkout, and starts with zero inventory.
- The replacement checkout is bound to the intended router, marketplace, FAME, USDC, and WETH contracts.
- The legacy marketplace is paused, while the sole provider position remains unchanged for later UI-driven withdrawal.
- Stale creator and legacy-market write roles are revoked from V2.
- `tokenURI` parity holds across Society token IDs 1 through 888.

The provider wallet may now use the legacy recovery UI to withdraw from the old marketplace and then stake through the active marketplace flow. This deployment did not move that position.
