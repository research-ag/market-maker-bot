import { useEffect, useMemo } from 'react';
import { Controller, SubmitHandler, useForm, useFormState } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z as zod } from 'zod';
import { Box, Button, FormControl, FormLabel, Input, Modal, ModalClose, ModalDialog, Typography } from '@mui/joy';

import { useAddPair } from '../../../integration';
import { ErrorAlert } from '../../error-alert';

interface AddPairFormValues {
  principal: string;
  symbol: string;
  decimals: number;
  spread_value: number;
}

interface AddPairModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const schema = zod.object({
  principal: zod
    .string()
    .min(1),
  symbol: zod
    .string()
    .min(1),
  decimals: zod
    .string()
    .min(0)
    .refine((value: string) => !isNaN(Number(value))),
  spread_value: zod
    .string()
    .min(0)
    .refine((value: string) => !isNaN(Number(value))),
});

export const AddPairModal = ({ isOpen, onClose }: AddPairModalProps) => {
  const defaultValues: AddPairFormValues = useMemo(
    () => ({
      principal: '',
      symbol: '',
      decimals: 0,
      spread_value: 0,
    }),
    [],
  );

  const {
    handleSubmit,
    control,
    reset: resetForm,
  } = useForm<AddPairFormValues>({
    defaultValues,
    resolver: zodResolver(schema),
    mode: 'onChange',
  });

  const { isDirty, isValid } = useFormState({ control });

  const { mutate: addPair, error, isLoading, reset: resetApi } = useAddPair();

  const submit: SubmitHandler<AddPairFormValues> = data => {
    data.decimals = Number(data.decimals);
    data.spread_value = Number(data.spread_value);
    addPair(data, {
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
      <ModalDialog sx={{ width: 'calc(100% - 50px)', maxWidth: '450px' }}>
        <ModalClose />
        <Typography level="h4">Add pair</Typography>
        <form onSubmit={handleSubmit(submit)} autoComplete="off">
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <Controller
              name="symbol"
              control={control}
              render={({ field, fieldState }) => (
                <FormControl>
                  <FormLabel>Base token symbol</FormLabel>
                  <Input
                    type="text"
                    variant="outlined"
                    name={field.name}
                    value={field.value}
                    onChange={field.onChange}
                    autoComplete="off"
                    error={!!fieldState.error}
                  />
                </FormControl>
              )}
            />
            <Controller
              name="principal"
              control={control}
              render={({ field, fieldState }) => (
                <FormControl>
                  <FormLabel>Base token principal</FormLabel>
                  <Input
                    type="text"
                    variant="outlined"
                    name={field.name}
                    value={field.value}
                    onChange={field.onChange}
                    autoComplete="off"
                    error={!!fieldState.error}
                  />
                </FormControl>
              )}
            />
            <Controller
              name="decimals"
              control={control}
              render={({ field, fieldState }) => (
                <FormControl>
                  <FormLabel>Base token decimals</FormLabel>
                  <Input
                    type="text"
                    variant="outlined"
                    name={field.name}
                    value={field.value}
                    onChange={field.onChange}
                    autoComplete="off"
                    error={!!fieldState.error}
                  />
                </FormControl>
              )}
            />
          </Box>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <Controller
              name="spread_value"
              control={control}
              render={({ field, fieldState }) => (
                <FormControl>
                  <FormLabel>Spread value in percent</FormLabel>
                  <Input
                    type="text"
                    variant="outlined"
                    name={field.name}
                    value={field.value}
                    onChange={field.onChange}
                    autoComplete="off"
                    error={!!fieldState.error}
                  />
                </FormControl>
              )}
            />
          </Box>
          {!!error && <ErrorAlert errorMessage={(error as Error).message} />}
          <Button
            sx={{ marginTop: 2 }}
            variant="solid"
            loading={isLoading}
            type="submit"
            disabled={!isValid || !isDirty}>
            Add
          </Button>
        </form>
      </ModalDialog>
    </Modal>
  );
};
