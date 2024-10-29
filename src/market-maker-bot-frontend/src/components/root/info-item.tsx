import {useRef, useState} from 'react';
import {Box, Tooltip, Typography} from '@mui/joy';
import { Edit, Refresh, ContentCopy } from '@mui/icons-material';

interface InfoItemProps {
    label?: string;
    content: string;
    withCopy?: boolean;
    withRefresh?: boolean;
    onRefresh?: () => void;
    withEdit?: boolean;
    onEdit?: () => void;
}

const InfoItem = ({label, content, withCopy, withRefresh, onRefresh, withEdit, onEdit}: InfoItemProps) => {
    const timerID = useRef<any>(null);

    const [isCopied, setIsCopied] = useState(false);

    const copyTooltipTitle = isCopied ? '✓ Copied' : 'Copy to clipboard';

    return (
        <Box sx={{display: 'flex', alignItems: 'center', gap: 0.5}}>
            <Typography sx={{fontWeight: 700}} level="body-xs">
                {label ? `${label}: ` : ''}
            </Typography>
            <Typography level="body-xs">{content}</Typography>
            {withCopy && (
                <Tooltip title={copyTooltipTitle} disableInteractive>
                    <ContentCopy
                        sx={{fontSize: '16px', cursor: 'pointer', marginLeft: 1}}
                        onClick={() => {
                            const clipboardItem = new ClipboardItem({
                                'text/plain': new Blob([content], {type: 'text/plain'}),
                            });

                            navigator.clipboard.write([clipboardItem]);

                            if (timerID.current) {
                                clearTimeout(timerID.current);
                            }

                            setIsCopied(true);

                            timerID.current = setTimeout(() => {
                                setIsCopied(false);
                            }, 3000);
                        }}
                    />
                </Tooltip>
            )}
            {withRefresh && (
                <Tooltip title="Refresh" disableInteractive>
                    <Refresh sx={{fontSize: '16px', cursor: 'pointer', marginLeft: 1}} onClick={onRefresh}/>
                </Tooltip>
            )}
            {withEdit && (
                <Tooltip title="Edit" disableInteractive>
                    <Edit sx={{fontSize: '16px', cursor: 'pointer', marginLeft: 1}} onClick={onEdit}/>
                </Tooltip>
            )}
        </Box>
    );
};

export default InfoItem;
