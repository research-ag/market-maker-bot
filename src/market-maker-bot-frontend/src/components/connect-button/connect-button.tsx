import {useEffect, useLayoutEffect, useState} from 'react';
import {AuthClient} from '@dfinity/auth-client';
import {Button} from '@mui/joy';

import {useIdentity} from '../../integration/identity';

const ConnectButton = () => {
    const [authClient, setAuthClient] = useState<AuthClient | null>(null);

    const {identity, setIdentity} = useIdentity();

    const isConnected = identity.getPrincipal().toText() !== '2vxsx-fae';

    useLayoutEffect(() => {
        AuthClient.create().then(setAuthClient);
    }, []);

    useEffect(() => {
        if (authClient) {
            const identity = authClient.getIdentity();
            setIdentity(identity);
        }
    }, [authClient]);

    const handleConnect = () => {
        if (!authClient) {
            return;
        }

        authClient.login({
            onSuccess: () => {
                const identity = authClient.getIdentity();
                setIdentity(identity);
            },
            identityProvider: 'https://identity.ic0.app/#authorize',
            windowOpenerFeatures:
                `left=${window.screen.width / 2 - 525 / 2}, ` +
                `top=${window.screen.height / 2 - 705 / 2},` +
                `toolbar=0,location=0,menubar=0,width=525,height=705`,
        });
    };

    const handleDisconnect = () => {
        if (!authClient) {
            return;
        }

        authClient.logout().then(() => {
            const identity = authClient.getIdentity();
            setIdentity(identity);
        });
    };

    return (
        <Button onClick={!isConnected ? handleConnect : handleDisconnect} color={!isConnected ? 'success' : 'danger'}>
            {!isConnected ? 'Login' : 'Logout'}
        </Button>
    );
};

export default ConnectButton;
