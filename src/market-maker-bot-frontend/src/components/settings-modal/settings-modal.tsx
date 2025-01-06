import {useEffect, useMemo, useState} from 'react';
import {SubmitHandler, useFieldArray, useForm, useFormState} from 'react-hook-form';
import {zodResolver} from '@hookform/resolvers/zod';
import {z as zod} from 'zod';
import {Box, Button, FormControl, FormLabel, Input, Modal, ModalClose, ModalDialog, Typography} from '@mui/joy';
import {useUpdateTradingPairSettings} from "../../integration";
import {ErrorAlert} from "../error-alert";
import {MarketPairShared} from "../../declarations/market-maker-bot-backend/market-maker-bot-backend.did";

interface SettingsFormValues {
    strategy: {
        spread: string;
        spreadBias: string;
        weight: string;
    }[];
}

interface SettingsModalProps {
    pair: MarketPairShared;
    isOpen: boolean;
    onClose: () => void;
}

const schema = zod.object({
    strategy: zod.array(
        zod.object({
            spread: zod
                .string()
                .refine((value) => !isNaN(Number(value)) && Number(value) > 0 && Number(value) <= 1, {
                    message: "Spread must be a number between 0 and 1.",
                }),
            spreadBias: zod
                .string()
                .refine((value) => !isNaN(Number(value)) && Number(value) >= -1 && Number(value) <= 1, {
                    message: "Spread bias must be a number between -1 and 1.",
                }),
            weight: zod.string().refine((value) => !isNaN(Number(value)) && Number(value) > 0, {
                message: "Weight must be a positive number.",
            }),
        })
    ),
});

const SettingsModal = ({pair, isOpen, onClose}: SettingsModalProps) => {
    const defaultValues: SettingsFormValues = useMemo(() => {
        if (pair?.strategy) {
            return {
                strategy: pair.strategy.map(([[spread, spreadBias], weight]) => ({
                    spread: spread.toString(),
                    spreadBias: spreadBias.toString(),
                    weight: weight.toString(),
                })),
            };
        }
        return {
            strategy: [
                {
                    spread: "0.05",
                    spreadBias: "0.0",
                    weight: "1.0",
                },
            ],
        };
    }, [pair]);

    const {handleSubmit, control, reset: resetForm, watch} = useForm<SettingsFormValues>({
        defaultValues,
        resolver: zodResolver(schema),
        mode: "onChange",
    });

    const {fields: strategyFields, remove: removeStrategy, append: appendStrategy} = useFieldArray({
        control,
        name: "strategy",
    });

    const {isDirty, isValid} = useFormState({control});
    const {mutate: update, error, isLoading, reset: resetApi} = useUpdateTradingPairSettings();

    const [pricePrediction, setPricePrediction] = useState<[number, number, number][]>([]);

    useEffect(() => {
        const subscription = watch((values) => {
            setPricePrediction(
                values.strategy?.map((v) => [
                    1 + (v?.spreadBias ? +v.spreadBias : 0) + (v?.spread ? +v.spread : 0),
                    1 + (v?.spreadBias ? +v.spreadBias : 0) - (v?.spread ? +v.spread : 0),
                    v?.weight ? +v.weight : 0,
                ]) || []
            );
        });
        return () => subscription.unsubscribe();
    }, [watch]);

    const submit: SubmitHandler<SettingsFormValues> = ({strategy}) => {
        update({baseSymbol: pair.base.symbol, strategy}, {onSuccess: () => onClose()});
    };

    useEffect(() => {
        resetForm(defaultValues);
        resetApi();
    }, [isOpen]);

    return (
        <Modal open={isOpen} onClose={onClose}>
            <ModalDialog sx={{width: "calc(100% - 50px)", maxWidth: "650px", maxHeight: '80%'}}>
                <ModalClose/>
                <Typography level="h4">Update {pair.base.symbol} settings</Typography>
                <form onSubmit={handleSubmit(submit)} autoComplete="off" style={{overflowY: 'auto'}}>
                    <Box sx={{display: "flex", flexDirection: "column", gap: 2}}>
                        {strategyFields.map((field, index) => (
                            <div key={field.id} style={{display: "flex", flexDirection: "column", gap: 1}}>
                                <FormControl>
                                    <FormLabel>Spread</FormLabel>
                                    <Input
                                        type="number"
                                        {...control.register(`strategy.${index}.spread`)}
                                        error={!!error}
                                        slotProps={{
                                            input: {min: 0, max: 1, step: 0.0001},
                                        }}
                                    />
                                </FormControl>
                                <FormControl>
                                    <FormLabel>Spread Bias</FormLabel>
                                    <Input
                                        type="number"
                                        {...control.register(`strategy.${index}.spreadBias`)}
                                        error={!!error}
                                        slotProps={{
                                            input: {min: -1, max: 1, step: 0.0001},
                                        }}
                                    />
                                </FormControl>
                                <FormControl>
                                    <FormLabel>Weight</FormLabel>
                                    <Input
                                        type="number"
                                        {...control.register(`strategy.${index}.weight`)}
                                        error={!!error}
                                        slotProps={{
                                            input: {min: 0.01, step: 0.01},
                                        }}
                                    />
                                </FormControl>
                                <Button variant="soft" color="danger" sx={{marginTop: 2}}
                                        onClick={() => removeStrategy(index)}>
                                    Remove
                                </Button>
                            </div>
                        ))}
                        <Button
                            variant="soft"
                            color="primary"
                            onClick={() =>
                                appendStrategy({
                                    spread: "0.05",
                                    spreadBias: "0.0",
                                    weight: "1.0",
                                })
                            }
                        >
                            Add Strategy
                        </Button>
                    </Box>
                    {!!error && <ErrorAlert errorMessage={(error as Error).message}/>}
                    <Typography level="body-xs">
                        {pricePrediction.map((p, i) => (
                            <p key={i}>
                                Ask price: <b>rate * {p[0].toFixed(4)}</b> | Bid price: <b>rate
                                * {p[1].toFixed(4)}</b> | Volume:{" "}
                                <b>balance * {p[2].toFixed(4)}</b>
                            </p>
                        ))}
                    </Typography>
                    <Button
                        sx={{marginTop: 2}}
                        variant="solid"
                        loading={isLoading}
                        type="submit"
                        disabled={!isValid || !isDirty}
                    >
                        Update
                    </Button>
                </form>
            </ModalDialog>
        </Modal>
    );
};

export default SettingsModal;
