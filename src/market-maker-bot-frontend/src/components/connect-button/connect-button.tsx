import {useEffect, useState} from 'react';
import {AuthClient} from '@icp-sdk/auth/client';
import {Button} from '@mui/joy';

import {useIdentity} from '../../integration/identity';

const ConnectButton = () => {
    const [authClient] = useState<AuthClient>(() => new AuthClient());

    const {identity, setIdentity} = useIdentity();

    const isConnected = identity.getPrincipal().toText() !== '2vxsx-fae';

    useEffect(() => {
        authClient.getIdentity().then(setIdentity);
    }, [authClient]);

    const handleConnect = async () => {
        const identity = await authClient.signIn();
        setIdentity(identity);
    };

    const handleDisconnect = async () => {
        await authClient.logout();
        const identity = await authClient.getIdentity();
        setIdentity(identity);
    };

    return (
        <Button onClick={!isConnected ? handleConnect : handleDisconnect} color={!isConnected ? 'success' : 'danger'}>
            {!isConnected ? 'Login' : 'Logout'}
        </Button>
    );
};

export default ConnectButton;
