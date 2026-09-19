declare module 'gifsicle-wasm-browser' {
  type GifsicleInput = {
    file: Blob | File | ArrayBuffer | string;
    name: string;
  };

  type GifsicleRunOptions = {
    input: GifsicleInput[];
    command: string[];
    folder?: string[];
    isStrict?: boolean;
  };

  const gifsicle: {
    run(options: GifsicleRunOptions): Promise<File[]>;
  };

  export default gifsicle;
}
