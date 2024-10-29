import {Box, Option, Select, Table} from '@mui/joy';

import {useGetHistory, useGetPairsList, useGetQuoteInfo} from '../../integration';
import {HistoryItemType} from '../../declarations/market-maker-bot-backend/market-maker-bot-backend.did';
import {displayWithDecimals} from '../../utils';
import {useEffect, useState} from "react";

const transformHistoryItem = (quoteDecimals: number, item: HistoryItemType) => {
    const timestamp = new Date(Number(item.timestamp / 1000000n));
    const bidOrder = item.bidOrder && item.bidOrder.length ? item.bidOrder[0] : null;
    const askOrder = item.askOrder && item.askOrder.length ? item.askOrder[0] : null;
    const spread = item.pair.spread_value;
    const baseToken = item.pair.base.symbol;
    const baseDecimals = item.pair.base.decimals;
    const normalize_factor = quoteDecimals - baseDecimals;
    const bidVolume = bidOrder?.amount ? displayWithDecimals(bidOrder?.amount, baseDecimals) : 'N/A';
    const askVolume = askOrder?.amount ? displayWithDecimals(askOrder?.amount, baseDecimals) : 'N/A';
    const bidPrice = bidOrder?.price ? (bidOrder?.price / 10 ** normalize_factor).toPrecision(5) : 'N/A';
    const askPrice = askOrder?.price ? (askOrder?.price / 10 ** normalize_factor).toPrecision(5) : 'N/A';

    return {
        timestamp,
        baseToken,
        spread,
        bidVolume,
        bidPrice,
        askVolume,
        askPrice,
        rate: item.rate ? item.rate[0]?.toPrecision(5) : 'N/A',
        message: item.message,
    };
}

export const OrdersHistory = () => {
    const [selectedToken, setSelectedToken] = useState<string | null>(null);
    const {data: history, isFetching: fetchingHistory, refetch: refetchHistory} = useGetHistory(selectedToken);
    const {data: quoteInfo, isFetching: fetchingQuoteInfo} = useGetQuoteInfo();
    const {data: pairsList, isFetching: fetchingPairsList} = useGetPairsList();

    useEffect(() => {
        refetchHistory();
    }, [selectedToken]);

    const handleTokenChange = (_: any, value: string | null) => {
        setSelectedToken((!value || value === 'all') ? null : value);
    };

    return (
        <Box sx={{width: '100%', overflow: 'auto'}}>
            <Box sx={{marginBottom: 2}}>
                <Select
                    value={selectedToken || 'all'}
                    onChange={handleTokenChange}
                    defaultValue={'all'}
                    disabled={fetchingPairsList}>
                    <Option key="all" value="all">All</Option>
                    {(pairsList ?? []).map((pair) => (
                        <Option key={pair.base.principal.toText()}
                                value={pair.base.principal.toText()}>{pair.base.symbol}</Option>
                    ))}
                </Select>
            </Box>
            <Table>
                <colgroup>
                    <col style={{width: '150px'}}/>
                    <col style={{width: '50px'}}/>
                    <col style={{width: '50px'}}/>
                    <col style={{width: '100px'}}/>
                    <col style={{width: '100px'}}/>
                    <col style={{width: '100px'}}/>
                    <col style={{width: '100px'}}/>
                    <col style={{width: '100px'}}/>
                </colgroup>
                <thead>
                <tr>
                    <th>Timestamp</th>
                    <th>Token</th>
                    <th>Spread</th>
                    <th>Rate</th>
                    <th>BID Volume</th>
                    <th>BID Price</th>
                    <th>ASK Volume</th>
                    <th>ASK Price</th>
                </tr>
                </thead>
                <tbody>
                {(fetchingHistory || fetchingQuoteInfo) && (
                    <tr>
                        <td colSpan={8}>Loading...</td>
                    </tr>
                )}
                {!fetchingHistory && !fetchingQuoteInfo && (history ?? []).map((item, i) => {
                    const {
                        timestamp,
                        baseToken,
                        spread,
                        bidVolume,
                        bidPrice,
                        askVolume,
                        askPrice,
                        rate,
                        message,
                    } = transformHistoryItem(quoteInfo?.decimals || 0, item);

                    return (
                        <tr key={i}>
                            <td>{timestamp.toLocaleString()}</td>
                            <td>{baseToken}</td>
                            <td>{spread}</td>
                            {item.message === 'OK' ? (
                                <>
                                    <td>{rate}</td>
                                    <td>{bidVolume}</td>
                                    <td>{bidPrice}</td>
                                    <td>{askVolume}</td>
                                    <td>{askPrice}</td>
                                </>
                            ) : (
                                <td colSpan={5}>{message}</td>
                            )}
                        </tr>
                    );
                })}
                </tbody>
            </Table>
        </Box>
    );
};
