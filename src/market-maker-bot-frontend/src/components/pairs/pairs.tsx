import { useState } from 'react';

import { PageTemplate } from '../page-template';
import { PairsTable } from './pairs-table';
import { AddPairModal } from './add-pair-modal';

export const Pairs = () => {
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const openAddModal = () => setIsAddModalOpen(true);
  const closeAddModal = () => setIsAddModalOpen(false);

  return (
    <PageTemplate
      title={'Pairs'}
      addButtonTitle={'Add new pair'}
      onAddButtonClick={openAddModal}>
      <PairsTable />
      <AddPairModal isOpen={isAddModalOpen} onClose={closeAddModal} />
    </PageTemplate>
  );
};
