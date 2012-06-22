module.exports = (mongoose)->
  Schema = mongoose.Schema
  ObjectID = mongoose.ObjectID
  
  Message = new Schema content: String
  Account = new Schema screen_name: String
                     , user_id: String
                     , oauth_token: String
                     , oauth_token_secret: String
                     , messages: [Message]
                     
  mongoose.model 'Message', Message
  
  Account:mongoose.model('Account', Account)
