import { useState } from 'react';
import { Button } from '@mui/joy';

import { useStartBot, useStopBot } from '../../integration';
import { ErrorAlert}  from '../error-alert';
import { SetTimerModal } from './set-timer-modal';

export const ToggleBotButton = (props : { isRunning: boolean, isFetching: boolean, currentTimer: BigInt }) => {
  const { mutate: startBot, error, isLoading: isStartLoading } = useStartBot();
  const { mutate: stopBot, isLoading: isStopLoading } = useStopBot();

  const [isStartModalOpen, setIsStartModalOpen] = useState(false);
  const openStartModal = () => setIsStartModalOpen(true);
  const closeStartModal = () => setIsStartModalOpen(false);

  const isStarted = !!props?.isRunning;
  const isLoading = !!props?.isFetching || isStartLoading || isStopLoading;

  const handleClick = () => {
    if (isStarted) {
      stopBot();
    } else {
      openStartModal();
    }
  };

  const handleSubmit = (timer: bigint) => {
    startBot(timer);
    closeStartModal();
  };

  return (
    <>
      {!!error && <ErrorAlert errorMessage={(error as Error).message} />}
      <Button onClick={handleClick} color={isLoading ? 'warning' : (!isStarted ? 'success' : 'danger')}>
        {isLoading ? (!isStarted ? 'Starting...' : 'Stopping...') : (!isStarted ? 'Start' : 'Stop')}
      </Button>
      <SetTimerModal isOpen={isStartModalOpen} onClose={closeStartModal} currentTimer={props.currentTimer} onSubmit={handleSubmit}/>
    </>
  );
};
