import { useState } from 'react';
import { fromHexString, toHexString } from './utils';

function Process({
  title = 'Select file to calculate hash',
  callbackBlob = () => Promise.resolve(),
  callbackHex = () => Promise.resolve(),
}) {
  const [loading, setLoading] = useState(false);
  const [hashString, setHashString] = useState(null);
  const [result, setResult] = useState(null);

  function handleSubmitBlob(event) {
    event.preventDefault();

    if (hashString === null) {
      alert('Empty hash!');
      return false;
    }

    setResult(null);
    setLoading(true);
    callbackBlob(fromHexString(hashString)).then((res) => {
      setResult(res);
      setLoading(false);
    }).catch((e) => { console.error(e); });

    return false;
  }

  function handleSubmitHex(event) {
    event.preventDefault();

    if (hashString === null) {
      alert('Empty hash!');
      return false;
    }

    setResult(null);
    setLoading(true);
    callbackHex(hashString).then((res) => {
      setResult(res);
      setLoading(false);
    }).catch((e) => { console.error(e); });

    return false;
  }

  const handleFileChange = (event) => {
    const selectedFile = event.target.files[0];
    setLoading(true);
    setResult(null);

    const reader = new FileReader();
    reader.onload = async (e) => {
      const hashBuffer = await crypto.subtle.digest('SHA-256', e.target.result);
      const uint8Array = new Uint8Array(hashBuffer);
      setHashString(toHexString(uint8Array));
      setLoading(false);
    };
    reader.readAsArrayBuffer(selectedFile);
  };

  const handleHashChange = (event) => {
    const newHashString = event.target.value;

    setHashString(newHashString);
  };

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
