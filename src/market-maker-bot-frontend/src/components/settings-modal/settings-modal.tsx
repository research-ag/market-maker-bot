import {useEffect, useMemo} from 'react';
import {Controller, SubmitHandler, useForm, useFormState} from 'react-hook-form';
import {zodResolver} from '@hookform/resolvers/zod';
import {z as zod} from 'zod';
import {Box, Button, FormControl, FormLabel, Input, Modal, ModalClose, ModalDialog, Typography,} from '@mui/joy';
import {useUpdateTradingPairSettings} from "../../integration";
import {ErrorAlert} from "../error-alert";
import {MarketPairShared} from "../../declarations/market-maker-bot-backend/market-maker-bot-backend.did";

interface SettingsFormValues {
    spread: number;
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
});

const SettingsModal = ({pair, isOpen, onClose}: SettingsModalProps) => {
    const defaultValues: SettingsFormValues = useMemo(
        () => ({spread: pair.spread_value}),
        [],
    );

    const {
        handleSubmit,
        control,
        reset: resetForm,
    } = useForm<SettingsFormValues>({
        defaultValues,
        resolver: zodResolver(schema),
        mode: 'onChange',
    });

    const {isDirty, isValid} = useFormState({control});
    const {mutate: update, error, isLoading, reset: resetApi} = useUpdateTradingPairSettings();

    const submit: SubmitHandler<SettingsFormValues> = ({spread}) => {
        update({baseSymbol: pair.base.symbol, spread: +spread}, {
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
                                        <FormLabel>Spread</FormLabel>
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
                                                    step: 0.01,
                                                },
                                            }}
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

export default SettingsModal;
