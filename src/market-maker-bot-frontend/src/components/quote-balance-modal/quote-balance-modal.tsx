import {useEffect, useMemo} from 'react';
import {Controller, SubmitHandler, useForm, useFormState} from 'react-hook-form';
import {zodResolver} from '@hookform/resolvers/zod';
import {z as zod} from 'zod';
import {Box, Button, FormControl, FormLabel, Input, Modal, ModalClose, ModalDialog, Typography,} from '@mui/joy';
import {useGetQuoteInfo, useUpdateTradingPairQuoteBalance} from "../../integration";
import {ErrorAlert} from "../error-alert";
import {MarketPairShared} from "../../declarations/market-maker-bot-backend/market-maker-bot-backend.did";

interface FormValues {
    balance: number;
}

interface ModalProps {
    pair: MarketPairShared;
    isOpen: boolean;
    onClose: () => void;
}

const schema = zod.object({
    balance: zod
        .string()
        .refine(value => !isNaN(Number(value)) && Number(value) >= 0),
});

const QuoteBalanceModal = ({pair, isOpen, onClose}: ModalProps) => {

    let {data: quoteInfo} = useGetQuoteInfo();

    const defaultValues: FormValues = useMemo(
        () => ({balance: Number(pair.quote_credits) / Math.pow(10, quoteInfo?.decimals || 0)}),
        [],
    );

    const {
        handleSubmit,
        control,
        reset: resetForm,
    } = useForm<FormValues>({
        defaultValues,
        resolver: zodResolver(schema),
        mode: 'onChange',
    });

    const {isDirty, isValid} = useFormState({control});
    const {mutate: update, error, isLoading, reset: resetApi} = useUpdateTradingPairQuoteBalance();

    const submit: SubmitHandler<FormValues> = ({balance}) => {
        update({baseSymbol: pair.base.symbol, balance: (+balance * Math.pow(10, quoteInfo?.decimals || 0))}, {
            onSuccess: () => {
                onClose();
            },
        });
    };

    useEffect(() => {
        resetForm(defaultValues);
        resetApi();
    }, [isOpen]);

    return (
        <Modal open={isOpen} onClose={onClose}>
            <ModalDialog sx={{width: 'calc(100% - 50px)', maxWidth: '450px'}}>
                <ModalClose/>
                <Typography level="h4">Update {pair.base.symbol} quote balance</Typography>
                <div style={{display: 'contents'}}>
                    <form onSubmit={handleSubmit(submit)} autoComplete="off">
                        <Box sx={{display: 'flex', flexDirection: 'column', gap: 1}}>
                            <Typography level="body-xs">
                                Note: quote asset uses {quoteInfo?.decimals || 0} decimals
                            </Typography>
                            <Controller
                                name="balance"
                                control={control}
                                render={({field, fieldState}) => (
                                    <FormControl>
                                        <FormLabel>Balance</FormLabel>
                                        <Input
                                            type="number"
                                            variant="outlined"
                                            name={field.name}
                                            value={field.value}
                                            slotProps={{
                                                input: {
                                                    step: 1 / Math.pow(10, quoteInfo?.decimals || 6),
                                                },
                                            }}
                                            onChange={field.onChange}
                                            autoComplete="off"
                                            error={!!fieldState.error}
                                        />
                                    </FormControl>
                                )}/>
                        </Box>
                        {!!error && <ErrorAlert errorMessage={(error as Error).message}/>}
                        <Button
                            sx={{marginTop: 2}}
                            variant="solid"
                            loading={isLoading}
                            type="submit"
                            disabled={!isValid || !isDirty}>
                            Update
                        </Button>
                    </form>
                </div>
            </ModalDialog>
        </Modal>
    );
};

export default QuoteBalanceModal;
