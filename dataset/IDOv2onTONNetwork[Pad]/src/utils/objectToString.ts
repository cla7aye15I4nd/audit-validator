export function objectToString(object: any) {
    return JSON.parse(JSON.stringify(object, (key, value) =>
        typeof value === 'bigint'
            ? value.toString()
            : value // return everything else unchanged
    ));
}