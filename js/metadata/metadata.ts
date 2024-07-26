export interface IAttributeString {
  value: string;
  trait_type: string;
  colors?: string[];
}

export interface IAttributeNumeric {
  value: number;
  trait_type: string;
  display_type?: "number" | "boost_number" | "boost_percentage";
}

export type IMetadataAttribute = IAttributeString | IAttributeNumeric;

export interface IMetadata {
  image: string;
  description?: string;
  tokenId?: string;
  external_url?: string;
  animation_url?: string;
  name: string;
  attributes?: IMetadataAttribute[];
  properties?: Record<string, string>;
  edition?: string | number;
  id?: string | number;
}
