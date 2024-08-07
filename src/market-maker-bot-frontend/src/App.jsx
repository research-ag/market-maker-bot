import { timestamp_backend } from 'declarations/timestamp_backend';

import Header from './Header';
import Process from './Process';

function App() {
  return (
    <>
      <Header />
      <main className="container">
        <div className="grid">
          <Process title={"Submit"}
            callbackBlob={async (hashValue) => {
              return timestamp_backend.submitBlob([hashValue]).then(([res]) => {
                return {
                  success: res,
                  message: res ? 'Hash successfully submitted' : 'Hash already exist, submitted previously',
                };
              }).catch((e) => ({
                success: false,
                message: e.message,
              }));
            }}
            callbackHex={async (hashValue) => {
              return timestamp_backend.submitHex([hashValue]).then(([res]) => {
                return {
                  success: res,
                  message: res ? 'Hash successfully submitted' : 'Hash already exist, submitted previously',
                };
              }).catch((e) => ({
                success: false,
                message: e.message,
              }));
            }}
          />
          <Process title={"Lookup"}
            callbackBlob={async (hashValue) => {
              return timestamp_backend.lookupBlob([hashValue]).then(([res]) => ({
                success: res !== 0n,
                message: res === 0n ? 'Hash not found' : `Hash submitted at ${new Date(Number(res) * 1000)}`,
              })).catch((e) => ({
                success: false,
                message: e.message,
              }));
            }}
            callbackHex={async (hashValue) => {
              return timestamp_backend.lookupHex([hashValue]).then(([res]) => ({
                success: res !== 0n,
                message: res === 0n ? 'Hash not found' : `Hash submitted at ${new Date(Number(res) * 1000)}`,
              })).catch((e) => ({
                success: false,
                message: e.message,
              }));
            }}
          />
        </div>
      </main>
      <footer className="container">
      </footer>
    </>
  );
}

export default App;
