import {useMutation, useQuery, useQueryClient} from 'react-query';
import {useSnackbar} from 'notistack';

import {useIdentity} from './identity';
import {canisterId as cid, createActor} from '../declarations/market-maker-bot-backend';
import {Principal} from "@dfinity/principal";

export const canisterId = cid;

export const useBot = () => {
    const {identity} = useIdentity();
    const bot = createActor(canisterId, {
        agentOptions: {
            identity,
            verifyQuerySignatures: false,
        },
    });
    return {bot};
};

export const useGetQuoteReserve = () => {
    const {bot} = useBot();
    const {enqueueSnackbar} = useSnackbar();
    return useQuery(
        'quoteReserve',
        async () => {
            return bot.queryQuoteReserve();
        },
        {
            onError: (err: unknown) => {
                enqueueSnackbar(`Failed to fetch bot state: ${err}`, {variant: 'error'});
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

export const useGetQuoteInfo = () => {
  const { bot } = useBot();
  const { enqueueSnackbar } = useSnackbar();
  return useQuery(
    'quoteInfo',
    async () => {
      return bot.getQuoteInfo();
    },
    {
      onError: (err: unknown) => {
        enqueueSnackbar(`Failed to fetch quote info: ${err}`, { variant: 'error' });
      },
    },
  );
};

export const useGetHistory = (token: string | null) => {
  const { bot } = useBot();
  const { enqueueSnackbar } = useSnackbar();
  return useQuery(
    'getHistory',
    async () => {
      return bot.getHistory(token ? [Principal.fromText(token)] : [], 1000n, 0n);
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

export const useStartBot = () => {
  const { bot } = useBot();
  const queryClient = useQueryClient();
  const { enqueueSnackbar } = useSnackbar();
  return useMutation(
    (timer: bigint) => bot.startBot(timer),
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

export const useUpdateTradingPairSettings = () => {
    const {bot} = useBot();
    const queryClient = useQueryClient();
    const {enqueueSnackbar} = useSnackbar();
    return useMutation(
        ({baseSymbol, spread}: { baseSymbol: string, spread: number }) => bot.setSpreadValue(baseSymbol, spread),
        {
            onSuccess: () => {
                queryClient.invalidateQueries('getPairsList');
            },
            onError: (err: unknown) => {
                enqueueSnackbar(`Failed to update trading pair settings: ${err}`, {variant: 'error'});
            },
        },
    );
};

export const useUpdateTradingPairQuoteBalance = () => {
    const {bot} = useBot();
    const queryClient = useQueryClient();
    const {enqueueSnackbar} = useSnackbar();
    return useMutation(
        ({baseSymbol, balance}: {
            baseSymbol: string,
            balance: number
        }) => bot.setQuoteBalance(baseSymbol, {set: BigInt(balance)}),
        {
            onSuccess: () => {
                queryClient.invalidateQueries('getPairsList');
                queryClient.invalidateQueries('quoteReserve');
            },
            onError: (err: unknown) => {
                enqueueSnackbar(`Failed to update trading pair quote balance: ${err}`, {variant: 'error'});
            },
        },
    );
};
