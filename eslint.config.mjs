import {configs as yaml} from "eslint-plugin-yml"
import prettier from "eslint-plugin-prettier/recommended";

export default [
    prettier,
    ...yaml["flat/prettier"],
    ...yaml["flat/standard"],
    {
        name: "yaml",
        rules: {
            "yml/file-extension": "error",
        }
    }
];
