create or replace function private.create_model_view(model_name text) returns void as $$
/* Copyright (c) 1999-2011 by OpenMFG LLC, d/b/a xTuple. 
   See www.xm.ple.com/CPAL for the full text of the software license. */

  // ..........................................................
  // METHODS
  //

    /* Pass an argument to change camel case names to snake case.
     A string passed in simply returns a decamelized string.
     If an object is passed, an object is returned with all it's
     proprety names camelized.

     @param {String | Object}
     @returns {String | Object} The argument modified
  */
  decamelize = function(arg) {
    var ret = arg; 

    decamelizeStr = function(str) {
      return str.replace((/([a-z])([A-Z])/g), '$1_$2').toLowerCase();
    }

    if(typeof arg == "string") {
      ret = decamelizeStr(arg);
    } else if(typeof arg == "object") {
      ret = new Object;

      for(var prop in arg) {
        ret[decamelizeStr(prop)] = arg[prop];
      }
    }

    return ret;
  }
  
  processModel = function(model) {
    var props = model.properties,
        view_name = model.nameSpace.toLowerCase() + '.' + model_name,
        insTgtCols = [], insSrcCols = [], updCols = [], pKeyCol, pKeyAlias,
        canCreate = model.canCreate !== false ? true : false,
        canUpdate = model.canUpdate !== false ? true : false,
        canDelete = model.canDelete !== false ? true : false;

    for(var i = 0; i < props.length; i++) {
      var col, alias = decamelize(props[i].name);
      
      /* process attributes */
      if(props[i].attr && props[i].attr.column) {
        var isVisible = props[i].attr.isVisible !== false ? true : false,
            isEditable = props[i].attr.isEditable !== false ? true : false,
            isPrimaryKey = props[i].attr.isPrimaryKey ? true : false;   

        if(isVisible) {
          col = 't' + tbl + '.' + props[i].attr.column + ' as "' + alias + '"';
          cols.push(col);
        }

        /* for update and delete rules */
        if(isPrimaryKey) {
          pKeyCol = props[i].attr.column;
          pKeyAlias = alias;
        }

        /* handle fixed value */
        if(props[i].attr.value) {
          var value = isNaN(props[i].attr.value - 0) ? "'" + props[i].attr.value + "'" : props[i].attr.value;

          /* for select */     
          clauses.push(props[i].attr.column + ' = ' + value);
          
          /* for insert */
          insSrcCols.push(value);
        }
        else insSrcCols.push('new.' + alias);

        /* for insert rule */
        insTgtCols.push(props[i].attr.column);

        /* for update rule */
        if(isVisible && isEditable && !isPrimaryKey) updCols.push(props[i].attr.column + ' = new.' + alias);
      }

      /* process toOne */
      if(props[i].toOne && props[i].toOne.column) {
        var table = decamelize(props[i].toOne.type),
            type = table.replace((/\w+\./i),''),
            inverse = props[i].toOne.inverse ? props[i].toOne.inverse : 'guid';
            
        col = '(select ' + type + ' from ' + table + ' where ' + type + '.' + inverse + ' = ' + props[i].toOne.column + ') as "' + alias + '"';
        cols.push(col);
      }

      /* process toMany */
      if(props[i].toMany && props[i].toMany.column) {
        var table = decamelize(props[i].toMany.type),
            type = table.replace((/\w+\./i),''),
            inverse = props[i].toMany.inverse ? props[i].toMany.inverse : 'guid';
            
        col = 'array(select ' + type + ' from ' + table + ' where ' + type + '.' + inverse + ' = ' + props[i].toMany.column + ') as "' + alias + '"';
        cols.push(col);
      }
    }

    /* process for base model */
    if(!model.context) {
      /* table */
      tbls.push(model.table + ' t' + tbl);

      /* build crud rules */
      var inspre = 'create rule "_CREATE" as on insert to ' + view_name + ' do instead ';
          updpre = 'create rule "_UPDATE" as on update to ' + view_name + ' do instead ';
          delpre = 'create rule "_DELETE" as on delete to ' + view_name + ' do instead ';
          
      if(model.privileges || model.isNested) {
        var rule;
        
        /* insert rule */
        rule = canCreate ? 
               inspre + 'insert into ' + model.table + '(' + insTgtCols.join(',') + ') values (' + insSrcCols.join(',') + ')' :
               inspre + 'nothing;';

        rules.push(rule);

        /* update rule */
        rule = canUpdate && pKeyCol ? 
               updpre + 'update ' + model.table + ' set ' + updCols.join(',') + ' where ' + pKeyCol + ' = old.' + pKeyAlias :
               updpre + 'nothing;';

        rules.push(rule); 

        /* delete rule */
        rule = canDelete && pKeyCol ?
               delpre + 'delete from ' + model.table + ' where ' + pKeyCol + ' = old.' + pKeyAlias :
               delpre + 'nothing;';

        rules.push(rule);
             
      } else {
        rules.push(inspre + 'nothing;');
        rules.push(updpre + 'nothing;');
        rules.push(delpre + 'nothing;');
      }
    }
    /* handle extension */
    else if(model.joinType && model.joinClause) {
      tbls.push(model.joinType + ' ' + model.table + ' on (' + model.joinClause + ')');
    } else tbls.push(', ' + model.table);
 
    if(model.clauses) clauses.push(model.conditions);

    if(model.order) orderBy.push(model.order);

    if(model.comment) comments = comments.concat('\n', model.comment);

    tbl++;
    
  }

  // ..........................................................
  // PROCESS
  //

  var cols = [], tbls = [], clauses = [], orderBy = [],
  comments = 'System view generated by model tables: WARNING! Do not make changes, add rules or dependencies directly to this view!',
  rules = [], query = '', tbl = 1 - 0, sql, base, extensions = [],
  debug = true;

  /* base model */
  sql = 'select model_id as id, model_json as json '
      + 'from private.modelbas '
      + 'where model_name = $1 '
      + ' and model_active '

  base = JSON.parse(executeSql(sql, [model_name])[0].json);

  processModel(base);
 
  /* model extensions */
  sql = 'select model_id as id, model_json as json '
      + 'from private.modelext '
      + 'where model_name = $1 '
      + ' and model_active '
      + 'order by modelext_seq, model_id '

  extensions = executeSql(sql, [model_name]);
  for(var i; i < extensions.length; i++) {
    processModel(JSON.parse(extensions[i].json));
  }
  
  /* Validate colums */
  if(!cols.length) throw new Error('There must be at least one column defined on the model.');
 
  /* Build query to create the new view */
  query = query.concat( 'create view ' + base.nameSpace.toLowerCase() + '.' + model_name, ' as ',
                        'select ', cols.join(', '),
                        ' from ', tbls.join(' '));
                     
  if(clauses.length) query = query.concat(' where ', clauses.join(' and '));
  if(orderBy.length) query = query.concat(' order by ', orderBy.join(' , '));

  if(debug) print(NOTICE, 'query', query);

  executeSql(query);

  /* Add comment */
  query = "comment on view xm." + model_name + " is '" + comments + "'"; 
  executeSql(query);
  
  /* Apply the rules */
  for(var i = 0; i < rules.length; i++) {
    executeSql(rules[i]);
  }

  /* Grant access to xtrole */
  query = 'grant all on xm.' + model_name + ' to xtrole';
  executeSql(query);


$$ language plv8;