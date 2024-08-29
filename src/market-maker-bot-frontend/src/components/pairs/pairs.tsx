import { useState } from 'react';

import { PageTemplate } from '../page-template';
import { PairsTable } from './pairs-table';

export const Pairs = () => {
  return (
    <PageTemplate title={'Pairs'}>
      <PairsTable />
    </PageTemplate>
  );
};
