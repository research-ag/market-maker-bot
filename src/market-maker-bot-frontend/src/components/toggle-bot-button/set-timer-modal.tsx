import { useEffect, useMemo } from 'react';
import { Controller, SubmitHandler, useForm, useFormState } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z as zod } from 'zod';
import { Box, Button, FormControl, FormLabel, Input, Modal, ModalClose, ModalDialog, Typography } from '@mui/joy';

interface SetTimerValues {
  timer: string;
}

interface SetTimerProps {
  currentTimer: BigInt;
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (timer: bigint) => void;
}

const schema = zod.object({
  timer: zod
    .string()
    .min(1)
    .refine(value => !isNaN(Number(value))),
});

export const SetTimerModal = ({ isOpen, onClose, onSubmit, currentTimer }: SetTimerProps) => {
  const defaultValues: SetTimerValues = useMemo(
    () => ({
      timer: currentTimer.toString(),
    }),
    [],
  );

  const {
    handleSubmit,
    control,
    reset: resetForm,
  } = useForm<SetTimerValues>({
    defaultValues,
    resolver: zodResolver(schema),
    mode: 'onChange',
  });

  const { isDirty, isValid } = useFormState({ control });

  const submit: SubmitHandler<SetTimerValues> = data => {
    onSubmit(BigInt(data.timer));
  };

  useEffect(() => {
    resetForm(defaultValues);
  }, [isOpen]);

  return (
    <Modal open={isOpen} onClose={onClose}>
      <ModalDialog sx={{ width: 'calc(100% - 50px)', maxWidth: '450px' }}>
        <ModalClose />
        <Typography level="h4">Set timer in seconds</Typography>
        <form onSubmit={handleSubmit(submit)} autoComplete="off">
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <Controller
              name="timer"
              control={control}
              render={({ field, fieldState }) => (
                <FormControl>
                  <FormLabel>Timer value</FormLabel>
                  <Input
                    type="number"
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
          <Button
            sx={{ marginTop: 2 }}
            variant="solid"
            type="submit"
            disabled={!isValid || !isDirty}>
            Start
          </Button>
        </form>
      </ModalDialog>
    </Modal>
  );
};
