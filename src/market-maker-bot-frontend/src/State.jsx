import { useEffect, useState } from 'react';
import { fromHexString, toHexString } from './utils';

function State({
  loadPairsList = () => Promise.resolve([]),
}) {
  const [loading, setLoading] = useState(false);
  const [pairsList, setPairsList] = useState([]);

  useEffect(() => {
    setLoading(true);
    loadPairsList().then((res) => {
      setPairsList(res);
    }).catch(() => {
      console.error('Error loading pairs');
    }).then(() => {
      setLoading(false);
    })
  }, []);

  return (
    <>
      <h3>{title}</h3>
      <label htmlFor="fileInput">Select file</label>
      <input type="file" id="submitFileInput" onChange={handleFileChange} disabled={loading} />
      <label htmlFor="submitHashInput">Or input hash manually</label>
      <input type="text" id="hashInput" placeholder="Input hash manually" disabled={loading} value={hashString ?? ''} onChange={handleHashChange} />
      <button onClick={handleSubmitBlob} disabled={loading && !!hashString}>Submit as binary</button>
      <button onClick={handleSubmitHex} disabled={loading && !!hashString}>Submit as hex string</button>
      {!!result && (
        <div className={result?.success ? 'success' : 'error'}>
          <label>{result?.message ?? ''}</label>
        </div>
      )}
    </>
  );
}

export default Process;
