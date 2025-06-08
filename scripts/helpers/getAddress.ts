import { getSigner } from "./getSigner";

export const getAddress = ({ secretKey }: { secretKey: string }) => {
  const signer = getSigner({ secretKey });
  return signer.toSuiAddress();
};