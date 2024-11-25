import {useEffect, useMemo, useState} from 'react';
import {Controller, SubmitHandler, useForm, useFormState} from 'react-hook-form';
import {zodResolver} from '@hookform/resolvers/zod';
import {z as zod} from 'zod';
import {Box, Button, FormControl, FormLabel, Input, Modal, ModalClose, ModalDialog, Typography,} from '@mui/joy';
import {useUpdateTradingPairSettings} from "../../integration";
import {ErrorAlert} from "../error-alert";
import {MarketPairShared} from "../../declarations/market-maker-bot-backend/market-maker-bot-backend.did";

interface SettingsFormValues {
    spread: number;
    spreadBias: number;
}

interface SettingsModalProps {
    pair: MarketPairShared;
    isOpen: boolean;
    onClose: () => void;
}

const schema = zod.object({
    spread: zod
        .string()
        .refine(value => !isNaN(Number(value)) && Number(value) > 0 && Number(value) <= 1),
    spreadBias: zod
        .string()
        .refine(value => !isNaN(Number(value)) && Number(value) >= -1 && Number(value) <= 1),
});

const SettingsModal = ({pair, isOpen, onClose}: SettingsModalProps) => {
    const defaultValues: SettingsFormValues = useMemo(
        () => ({spread: pair.spread?.[0] || 0.05, spreadBias: pair.spread?.[1] || 0.0}),
        [],
    );

    const {
        handleSubmit,
        control,
        reset: resetForm,
        watch,
    } = useForm<SettingsFormValues>({
        defaultValues,
        resolver: zodResolver(schema),
        mode: 'onChange',
    });

    const {isDirty, isValid} = useFormState({control});
    const {mutate: update, error, isLoading, reset: resetApi} = useUpdateTradingPairSettings();

    const [pricePrediction, setPricePrediction] = useState<[number, number]>([0, 0]);
    useEffect(() => {
        const {unsubscribe} = watch((v) => {
            setPricePrediction([
                1 + (v.spreadBias ? +v.spreadBias : 0) + (v.spread ? +v.spread : 0),
                1 + (v.spreadBias ? +v.spreadBias : 0) - (v.spread ? +v.spread : 0),
            ])
        });
        return () => unsubscribe();
    }, [watch]);

    const submit: SubmitHandler<SettingsFormValues> = ({spread, spreadBias}) => {
        update({baseSymbol: pair.base.symbol, spreadValue: +spread, spreadBias: +spreadBias}, {
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
                <Typography level="h4">Update {pair.base.symbol} settings</Typography>
                <div style={{display: 'contents'}}>
                    <form onSubmit={handleSubmit(submit)} autoComplete="off">
                        <Box sx={{display: 'flex', flexDirection: 'column', gap: 1}}>
                            <Controller
                                name="spread"
                                control={control}
                                render={({field, fieldState}) => (
                                    <FormControl>
                                        <FormLabel>Spread value</FormLabel>
                                        <Input
                                            type="number"
                                            variant="outlined"
                                            name={field.name}
                                            value={field.value}
                                            onChange={field.onChange}
                                            slotProps={{
                                                input: {
                                                    min: 0,
                                                    max: 1,
                                                    step: 0.0001,
                                                },
                                            }}
                                            autoComplete="off"
                                            error={!!fieldState.error}
                                        />
                                    </FormControl>
                                )}/>
                            <Controller
                                name="spreadBias"
                                control={control}
                                render={({field, fieldState}) => (
                                    <FormControl>
                                        <FormLabel>Spread bias</FormLabel>
                                        <Input
                                            type="number"
                                            variant="outlined"
                                            name={field.name}
                                            value={field.value}
                                            onChange={field.onChange}
                                            slotProps={{
                                                input: {
                                                    min: -1,
                                                    max: 1,
                                                    step: 0.0001,
                                                },
                                            }}
                                            autoComplete="off"
                                            error={!!fieldState.error}
                                        />
                                    </FormControl>
                                )}/>
                        </Box>
                        {!!error && <ErrorAlert errorMessage={(error as Error).message}/>}
                        <Typography level="body-xs">
                            Ask price: <b>rate * {pricePrediction[0].toFixed(4)}</b>
                            <br/>
                            Bid price: <b>rate * {pricePrediction[1].toFixed(4)}</b>
                            <br/>
                        </Typography>
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

export default SettingsModal;
