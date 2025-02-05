import { PageTemplate } from '../page-template';
import { PairsTable } from './pairs-table';
import { useNotifyActivityBotQuote } from '../../integration';

export const Pairs = () => {

  const { mutate: notifyActivityBot, isLoading } = useNotifyActivityBotQuote();

  return (
    <PageTemplate title={'Pairs'} addButtonTitle='Notify activity bot' onAddButtonClick={notifyActivityBot}
                  addButtonDisabled={isLoading}>
      <PairsTable/>
    </PageTemplate>
  );
};
