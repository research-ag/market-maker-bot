import { useMutation, useQuery, useQueryClient } from 'react-query';
import { useSnackbar } from 'notistack';

import { useIdentity } from './identity';
import { canisterId as cid, createActor } from '../declarations/market-maker-bot-backend';

// Custom replacer function for JSON.stringify
const bigIntReplacer = (key: string, value: any): any => {
  if (typeof value === 'bigint') {
    return `${value.toString()}n`; // Serialize BigInts as strings with 'n' suffix
  }
  return value;
};

export const canisterId = cid;

export const useBot = () => {
  const { identity } = useIdentity();
  const bot = createActor(canisterId, {
    agentOptions: {
      identity,
      verifyQuerySignatures: false,
    },
  });
  return { bot };
};

export const useListPairs = () => {
  const { bot } = useBot();
  const { enqueueSnackbar } = useSnackbar();
  return useQuery(
    'getPairs',
    async () => {
      return bot.getPairsList();
    },
    {
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to fetch pairs: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useBotState = () => {
  const { bot } = useBot();
  const { enqueueSnackbar } = useSnackbar();
  return useQuery(
    'getBotState',
    async () => {
      return bot.getBotState();
    },
    {
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to fetch pabot state: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useRemovePair = () => {
  const { bot } = useBot();
  const queryClient = useQueryClient();
  const { enqueueSnackbar } = useSnackbar();
  return useMutation(
    (pairIndex: number) => bot.removePairByIndex(BigInt(pairIndex)),
    {
      onSuccess: () => {
        queryClient.invalidateQueries('getPairs');
        enqueueSnackbar(`Pair removed`, { variant: 'success' });
      },
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to  pair: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useStartBot = () => {
  const { bot } = useBot();
  const queryClient = useQueryClient();
  const { enqueueSnackbar } = useSnackbar();
  return useMutation(
    () => bot.startBot(),
    {
      onSuccess: () => {
        queryClient.invalidateQueries('getBotState');
      },
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to start bot: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useStopBot = () => {
  const { bot } = useBot();
  const queryClient = useQueryClient();
  const { enqueueSnackbar } = useSnackbar();
  return useMutation(
    () => bot.stopBot(),
    {
      onSuccess: () => {
        queryClient.invalidateQueries('getBotState');
      },
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to stop bot: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useExecBot = () => {
  const { bot } = useBot();
  const queryClient = useQueryClient();
  const { enqueueSnackbar } = useSnackbar();
  return useMutation(
    () => bot.stopBot(),
    {
      onSuccess: () => {
        queryClient.invalidateQueries('getBotState');
      },
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to stop bot: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useAddPair = () => {
  const { bot } = useBot();
  const queryClient = useQueryClient();
  const { enqueueSnackbar } = useSnackbar();
  return useMutation(
    (formObj: {
      base_principal: string;
      base_symbol: string;
      base_decimals: number;
      quote_principal: string;
      quote_symbol: string;
      quote_decimals: number;
      spread_value: number;
    }) =>
      bot.addPair({
          principal: formObj.base_principal,
          decimals: formObj.base_decimals,
          symbol: formObj.base_symbol,
        },
        {
          principal: formObj.quote_principal,
          decimals: formObj.quote_decimals,
          symbol: formObj.quote_symbol,
        },
        formObj.spread_value,
      ),
    {
      onSuccess: () => {
        queryClient.invalidateQueries('getPairs');
        enqueueSnackbar(`Pair added`, { variant: 'success' });
      },
      onError: err => {
        enqueueSnackbar(`Failed to add pair: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useOrdersHistory = () => {
  const { bot } = useBot();
  const { enqueueSnackbar } = useSnackbar();
  return useQuery(
    'getOrdersHistory',
    async () => {
      return bot.getHistory();
    },
    {
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to fetch history: ${err}`, { variant: 'error' });
      },
    },
  );
};

