#!/bin/bash
set -euo pipefail

restart_canisters() {
  dfx canister start market-maker-bot-backend --ic
  dfx canister start activity-bot-backend_0 --ic
  dfx canister start activity-bot-backend_1 --ic
}

dfx canister stop market-maker-bot-backend --ic
dfx canister stop activity-bot-backend_0 --ic
dfx canister stop activity-bot-backend_1 --ic

if ! dfx deploy --ic; then
  echo "Deploy failed, restarting canisters..." >&2
  restart_canisters
  exit 1
fi

restart_canisters
