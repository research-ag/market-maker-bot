import { Button } from '@mui/joy';

import { useStartBot, useStopBot } from '../../integration';

export const ToggleBotButton = (props : { isRunning: boolean, isFetching: boolean }) => {
  const { mutate: startBot, isLoading: isStartLoading } = useStartBot();
  const { mutate: stopBot, isLoading: isStopLoading } = useStopBot();

  const isStarted = !!props?.isRunning;
  const isLoading = !!props?.isFetching || isStartLoading || isStopLoading;

  const handleClick = () => {
    if (isStarted) {
      stopBot();
    } else {
      startBot();
    }
  };

  return (
    <Button onClick={handleClick} color={isLoading ? 'warning' : (!isStarted ? 'success' : 'danger')}>
      {isLoading ? 'Loading...' : (!isStarted ? 'Start' : 'Stop')}
    </Button>
  );
};
