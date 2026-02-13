dfx canister stop market-maker-bot-backend --ic
dfx canister stop activity-bot-backend_0 --ic
dfx canister stop activity-bot-backend_1 --ic

dfx deploy --ic

dfx canister start market-maker-bot-backend --ic
dfx canister start activity-bot-backend_0 --ic
dfx canister start activity-bot-backend_1 --ic