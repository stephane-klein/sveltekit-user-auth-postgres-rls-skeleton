import yargs from "yargs/yargs";
import { hideBin } from "yargs/helpers";

import sql from "./db.js";

yargs(hideBin(process.argv))
    .command("user", "Manage users", (yargs) =>
        yargs.command(
            "create",
            "create a user",
            (yargs) =>
                yargs.options({
                    username: {
                        string: true,
                        demandOption: true
                    },
                    firstname: {
                        default: undefined,
                        string: true
                    },
                    lastname: {
                        default: undefined,
                        string: true
                    },
                    email: {
                        string: true,
                        demandOption: true
                    },
                    password: {
                        string: true,
                        demandOption: true
                    },
                    staff: {
                        boolean: true,
                        default: false
                    }
                }),
            async(argv) => {
                try {
                    await sql`
                        SELECT auth.create_user(
                            username   => ${argv.username},
                            first_name => ${argv?.firstname || ""},
                            last_name  => ${argv?.lastname || ""},
                            email      => ${argv.email},
                            password   => ${argv.password},
                            is_staff   => ${argv.staff},
                            is_active  => true
                        );
                    `;
                } catch (err) {
                    console.log(err.message);
                } finally {
                    sql.end();
                }
            }
        )
    )
    .parse();
