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

export const useAddPair = () => {
  const { bot } = useBot();
  const queryClient = useQueryClient();
  const { enqueueSnackbar } = useSnackbar();
  return useMutation(
    (formObj: {
      principal: string;
      symbol: string;
      decimals: number;
      spread_value: number;
    }) =>
      bot.addPair({
        principal: formObj.principal,
        decimals: formObj.decimals,
        symbol: formObj.symbol,
        spread_value: formObj.spread_value,
      }),
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

export const useExecuteMarketMaking = () => {
  const { bot } = useBot();
  const queryClient = useQueryClient();
  const { enqueueSnackbar } = useSnackbar();
  return useMutation(
    () => bot.executeMarketMaking(),
    {
      onSuccess: () => {
        queryClient.invalidateQueries('getHistory');
      },
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to stop bot: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useGetBotState = () => {
  const { bot } = useBot();
  const { enqueueSnackbar } = useSnackbar();
  return useQuery(
    'getBotState',
    async () => {
      return bot.getBotState();
    },
    {
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to fetch bot state: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useGetHistory = () => {
  const { bot } = useBot();
  const { enqueueSnackbar } = useSnackbar();
  return useQuery(
    'getHistory',
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

export const useGetPairsList = () => {
  const { bot } = useBot();
  const { enqueueSnackbar } = useSnackbar();
  return useQuery(
    'getPairsList',
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

export const useRemovePairByIndex = () => {
  const { bot } = useBot();
  const queryClient = useQueryClient();
  const { enqueueSnackbar } = useSnackbar();
  return useMutation(
    (pairIndex: number) => bot.removePairByIndex(BigInt(pairIndex)),
    {
      onSuccess: () => {
        queryClient.invalidateQueries('getPairsList');
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
