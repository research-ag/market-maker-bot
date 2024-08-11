import { Button } from '@mui/joy';

import { useBotState, useStartBot, useStopBot } from '../../integration';

export const ToggleBotButton = () => {
  const { data: botState, isFetching: isStateLoading } = useBotState();
  const { mutate: startBot, isLoading: isStartLoading } = useStartBot();
  const { mutate: stopBot, isLoading: isStopLoading } = useStopBot();

  const isStarted = !!botState?.running;
  const isLoading = isStateLoading || isStartLoading || isStopLoading;

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
