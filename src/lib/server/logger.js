import pino from "pino";
import pinoCaller from "pino-caller";

const logger = pinoCaller(
    pino({
        level: "debug",
        transport: {
            target: "pino-pretty",
            options: {
                colorize: true
            }
        }
    })
);

export default logger;
