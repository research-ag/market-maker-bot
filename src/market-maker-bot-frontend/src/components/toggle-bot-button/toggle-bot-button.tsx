import { useState } from 'react';
import { Button } from '@mui/joy';

import { useStartBot, useStopBot } from '../../integration';
import { SetTimerModal } from './set-timer-modal';

export const ToggleBotButton = (props : { isRunning: boolean, isFetching: boolean, currentTimer: BigInt }) => {
  const { mutate: stopBot, isLoading: isStopLoading } = useStopBot();
  const { isLoading: isStartLoading } = useStartBot();

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

  return (
    <>
      <Button onClick={handleClick} color={isLoading ? 'warning' : (!isStarted ? 'success' : 'danger')}>
        {isLoading ? 'Loading...' : (!isStarted ? 'Start' : 'Stop')}
      </Button>
      <SetTimerModal isOpen={isStartModalOpen} onClose={closeStartModal} currentTimer={props.currentTimer} />
    </>
  );
};
