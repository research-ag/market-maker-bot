import { Alert } from '@mui/joy';

interface ErrorAlertProps {
  errorMessage: string;
}

export const ErrorAlert = ({ errorMessage }: ErrorAlertProps) => {
  return (
    <Alert sx={{ overflow: 'auto', marginTop: 1 }} color="danger" size="sm">
      <pre style={{ margin: '0' }}>{errorMessage}</pre>
    </Alert>
  );
};
